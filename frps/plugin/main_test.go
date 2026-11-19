package main

import (
	"encoding/json"
	"fmt"
	"testing"
)

const adminToken = "admin-token-0123456789"

func testConfig() *Config {
	return &Config{
		AdminToken: adminToken,
		Users: []User{
			{Name: "anna", Token: "anna-token-0123456789", Subdomains: []string{"brite", "demo-*"}},
		},
	}
}

func loginJSON(user, token string) json.RawMessage {
	return json.RawMessage(fmt.Sprintf(
		`{"version":"0.72.0","user":%q,"privilege_key":"x","timestamp":1,"metas":{"token":%q},"client_address":"1.2.3.4:5"}`,
		user, token))
}

func TestLogin(t *testing.T) {
	c := testConfig()
	cases := []struct {
		name, user, token string
		ok                bool
	}{
		{"admin", "", adminToken, true},
		{"admin wrong token", "", "anna-token-0123456789", false},
		{"admin no token", "", "", false},
		{"anna", "anna", "anna-token-0123456789", true},
		{"anna with admin token", "anna", adminToken, false},
		{"unknown user", "bob", "bob-token-0123456789", false},
	}
	for _, tc := range cases {
		r := c.handleLogin(loginJSON(tc.user, tc.token))
		if r.Reject == tc.ok || (tc.ok && !r.Unchange) {
			t.Errorf("%s: got %+v, want ok=%v", tc.name, r, tc.ok)
		}
	}
	if r := c.handleLogin(json.RawMessage(`{"user":""}`)); !r.Reject {
		t.Error("login without metas must be rejected")
	}
}

func newProxyJSON(user, typ, sub string, extra string) json.RawMessage {
	return json.RawMessage(fmt.Sprintf(
		`{"user":{"user":%q,"metas":null,"run_id":"x"},"proxy_name":"p","proxy_type":%q,"subdomain":%q%s}`,
		user, typ, sub, extra))
}

func TestNewProxy(t *testing.T) {
	c := testConfig()
	cases := []struct {
		name, user, typ, sub, extra string
		ok                          bool
	}{
		{"admin anything", "", "tcp", "", `,"remote_port":6000`, true},
		{"exact subdomain", "anna", "http", "brite", "", true},
		{"pattern", "anna", "http", "demo-x", "", true},
		{"case-insensitive", "anna", "http", "BRITE", "", true},
		{"other subdomain", "anna", "http", "jf", "", false},
		{"no subdomain", "anna", "http", "", "", false},
		{"tcp", "anna", "tcp", "", `,"remote_port":6000`, false},
		{"custom domain", "anna", "http", "brite", `,"custom_domains":["evil.example.com"]`, false},
		{"group", "anna", "http", "brite", `,"group":"g"`, false},
		{"unknown user", "bob", "http", "brite", "", false},
	}
	for _, tc := range cases {
		r := c.handleNewProxy(newProxyJSON(tc.user, tc.typ, tc.sub, tc.extra))
		if r.Reject == tc.ok {
			t.Errorf("%s: got reject=%v (%s), want ok=%v", tc.name, r.Reject, r.RejectReason, tc.ok)
		}
	}
}

func TestValidate(t *testing.T) {
	bad := []Config{
		{AdminToken: "short"},
		{AdminToken: adminToken, Users: []User{{Name: "Anna", Token: "anna-token-0123456789"}}},
		{AdminToken: adminToken, Users: []User{{Name: "anna", Token: "short"}}},
		{AdminToken: adminToken, Users: []User{{Name: "anna", Token: adminToken}}},
		{AdminToken: adminToken, Users: []User{{Name: "anna", Token: "anna-token-0123456789"}, {Name: "anna", Token: "anna-token-9876543210"}}},
		{AdminToken: adminToken, Users: []User{{Name: "anna", Token: "anna-token-0123456789", Subdomains: []string{"["}}}},
	}
	for i, c := range bad {
		if c.validate() == nil {
			t.Errorf("config %d should be invalid", i)
		}
	}
	noAdmin := testConfig()
	noAdmin.AdminToken = ""
	if err := noAdmin.validate(); err != nil {
		t.Errorf("config without admin token rejected: %v", err)
	}
	if r := noAdmin.handleLogin(loginJSON("", "")); !r.Reject {
		t.Error("admin login must be rejected without an admin token")
	}
	if r := noAdmin.handleLogin(loginJSON("anna", "anna-token-0123456789")); r.Reject {
		t.Error("users must still sign in without an admin token")
	}
	if err := testConfig().validate(); err != nil {
		t.Errorf("valid config rejected: %v", err)
	}
}
