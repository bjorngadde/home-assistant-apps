// Command frps-users is an frps server plugin that adds per-user tokens and
// per-user subdomain rules to frps.
//
// frps derives its control-channel encryption key from auth.token, so every
// client must use the same auth.token. With users configured, frps therefore
// runs with an empty auth.token (the connection is still TLS-encrypted) and
// this plugin does the authentication on Login, using the client's
// `metadatas.token`:
//
//   - no `user`: the admin, whose token is the app's auth_token. The admin may
//     create any proxy. Without an auth_token there is no admin login.
//   - `user = "<name>"`: that user's own token. On NewProxy, users may only
//     create plain HTTP proxies on their own subdomains.
package main

import (
	"crypto/subtle"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"path"
	"regexp"
	"strings"
)

// User is one entry of the app's users option.
type User struct {
	Name       string   `json:"name"`
	Token      string   `json:"token"`
	Subdomains []string `json:"subdomains"`
}

// Config is written by the app's init script.
type Config struct {
	AdminToken string `json:"admin_token"`
	Users      []User `json:"users"`
}

var userNameRe = regexp.MustCompile(`^[a-z0-9][a-z0-9_-]{0,31}$`)

func loadConfig(file string) (*Config, error) {
	b, err := os.ReadFile(file)
	if err != nil {
		return nil, err
	}
	var cfg Config
	if err := json.Unmarshal(b, &cfg); err != nil {
		return nil, fmt.Errorf("parse %s: %w", file, err)
	}
	return &cfg, cfg.validate()
}

func (c *Config) validate() error {
	if c.AdminToken != "" && len(c.AdminToken) < 16 {
		return errors.New("admin token must be at least 16 characters")
	}
	seen := map[string]bool{}
	for _, u := range c.Users {
		if !userNameRe.MatchString(u.Name) {
			return fmt.Errorf("user %q: names may only use a-z, 0-9, '-' and '_' (max 32)", u.Name)
		}
		if seen[u.Name] {
			return fmt.Errorf("user %q is listed twice", u.Name)
		}
		seen[u.Name] = true
		if len(u.Token) < 16 {
			return fmt.Errorf("user %q: token must be at least 16 characters", u.Name)
		}
		if c.AdminToken != "" && u.Token == c.AdminToken {
			return fmt.Errorf("user %q: token must differ from auth_token", u.Name)
		}
		for _, p := range u.Subdomains {
			if _, err := path.Match(p, ""); err != nil {
				return fmt.Errorf("user %q: bad subdomain pattern %q", u.Name, p)
			}
		}
	}
	return nil
}

func (c *Config) user(name string) *User {
	for i := range c.Users {
		if c.Users[i].Name == name {
			return &c.Users[i]
		}
	}
	return nil
}

// Response is the frps plugin response.
type Response struct {
	Reject       bool   `json:"reject"`
	RejectReason string `json:"reject_reason,omitempty"`
	Unchange     bool   `json:"unchange"`
	Content      any    `json:"content,omitempty"`
}

type request struct {
	Op      string          `json:"op"`
	Content json.RawMessage `json:"content"`
}

func allow() Response { return Response{Unchange: true} }

func reject(format string, args ...any) Response {
	return Response{Reject: true, RejectReason: fmt.Sprintf(format, args...)}
}

// handleLogin checks the client's metadatas.token against the admin token
// (no user name) or the named user's token.
func (c *Config) handleLogin(raw json.RawMessage) Response {
	var content struct {
		User          string            `json:"user"`
		Metas         map[string]string `json:"metas"`
		ClientAddress string            `json:"client_address"`
	}
	if err := json.Unmarshal(raw, &content); err != nil {
		return reject("invalid login request")
	}
	name, addr := content.User, content.ClientAddress
	want := c.AdminToken
	who := "admin"
	if name == "" && want == "" {
		log.Printf("login rejected: admin login is disabled (no auth_token), from %s", addr)
		return reject("authorization failed")
	}
	if name != "" {
		u := c.user(name)
		if u == nil {
			log.Printf("login rejected: unknown user %q from %s", name, addr)
			return reject("authorization failed")
		}
		want, who = u.Token, fmt.Sprintf("user %q", name)
	}
	got := content.Metas["token"]
	if subtle.ConstantTimeCompare([]byte(got), []byte(want)) != 1 {
		log.Printf("login rejected: wrong or missing metadatas.token for %s from %s", who, addr)
		return reject("authorization failed")
	}
	log.Printf("login accepted: %s from %s", who, addr)
	return allow()
}

type newProxyContent struct {
	User struct {
		User string `json:"user"`
	} `json:"user"`
	ProxyName     string   `json:"proxy_name"`
	ProxyType     string   `json:"proxy_type"`
	SubDomain     string   `json:"subdomain"`
	CustomDomains []string `json:"custom_domains"`
	Group         string   `json:"group"`
}

// handleNewProxy limits named users to HTTP proxies on their own subdomains.
func (c *Config) handleNewProxy(raw json.RawMessage) Response {
	var p newProxyContent
	if err := json.Unmarshal(raw, &p); err != nil {
		return reject("invalid new proxy request")
	}
	name := p.User.User
	if name == "" {
		return allow()
	}
	u := c.user(name)
	if u == nil {
		return reject("unknown user")
	}
	deny := func(format string, args ...any) Response {
		r := reject(format, args...)
		log.Printf("proxy %q of user %q rejected: %s", p.ProxyName, name, r.RejectReason)
		return r
	}
	if p.ProxyType != "http" {
		return deny("user %s may only create http proxies", name)
	}
	if len(p.CustomDomains) > 0 {
		return deny("user %s may not use customDomains, use subdomain", name)
	}
	if p.Group != "" {
		return deny("user %s may not use load-balancing groups", name)
	}
	sub := strings.ToLower(p.SubDomain)
	if sub == "" {
		return deny("user %s must set a subdomain", name)
	}
	for _, pattern := range u.Subdomains {
		if ok, _ := path.Match(pattern, sub); ok {
			log.Printf("proxy %q of user %q allowed on subdomain %q", p.ProxyName, name, sub)
			return allow()
		}
	}
	return deny("subdomain %q is not allowed for user %s", sub, name)
}

func (c *Config) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req request
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&req); err != nil {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}
	var resp Response
	switch req.Op {
	case "Login":
		resp = c.handleLogin(req.Content)
	case "NewProxy":
		resp = c.handleNewProxy(req.Content)
	default:
		resp = allow()
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(resp)
}

func main() {
	listen := flag.String("listen", "127.0.0.1:7598", "address to listen on")
	configFile := flag.String("config", "/tmp/frps-users.json", "users config file")
	check := flag.Bool("check", false, "only validate the config file")
	flag.Parse()
	log.SetFlags(0)
	log.SetPrefix("[users] ")

	cfg, err := loadConfig(*configFile)
	if err != nil {
		log.Fatalf("invalid users config: %v", err)
	}
	if *check {
		return
	}
	names := make([]string, 0, len(cfg.Users))
	for _, u := range cfg.Users {
		names = append(names, u.Name)
	}
	log.Printf("listening on %s for %d user(s): %s", *listen, len(names), strings.Join(names, ", "))
	mux := http.NewServeMux()
	mux.Handle("/handler", cfg)
	log.Fatal(http.ListenAndServe(*listen, mux))
}
