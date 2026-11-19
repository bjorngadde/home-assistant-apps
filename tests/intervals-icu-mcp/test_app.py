"""Intervals.icu MCP app: option mapping, startup refusal, and file sanity.

Moved here from bjorngadde/intervals-icu-mcp (tests/test_ha_addon.py) together
with the app.
"""

import importlib.util
import json
import re
import sys
from pathlib import Path

import pytest
import yaml

REPO = Path(__file__).resolve().parents[2]
ADDON = REPO / "intervals-icu-mcp"

_spec = importlib.util.spec_from_file_location("ha_addon_run", ADDON / "run.py")
assert _spec and _spec.loader
run = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(run)

SECRET = "s" * 43


def _opts(**values: str) -> dict:
    base = {key: "" for key in run.OPTION_ENV}
    base["log_level"] = "info"
    base.update(values)
    return base


class TestEnvironmentMapping:
    def test_refuses_without_auth_mode(self):
        with pytest.raises(run.AddonConfigError) as exc:
            run.build_environment(_opts(api_key="k", athlete_id="i1"), {})
        assert "No authentication mode" in str(exc.value)

    def test_secret_mode_maps_env(self):
        env = run.build_environment(
            _opts(api_key="k", athlete_id="i1", path_secret=SECRET), {"PATH": "/bin"}
        )
        assert env["MCP_PATH_SECRET"] == SECRET
        assert env["INTERVALS_ICU_API_KEY"] == "k"
        assert env["INTERVALS_ICU_ATHLETE_ID"] == "i1"
        assert env["DATA_DIR"] == "/data"
        assert env["FORWARDED_ALLOW_IPS"] == "172.30.32.0/23,127.0.0.1"
        assert env["PATH"] == "/bin"
        assert "INTERVALS_OAUTH_CLIENT_ID" not in env  # empty options are not exported

    def test_delete_mode_maps_env(self):
        env = run.build_environment(
            _opts(api_key="k", athlete_id="i1", path_secret=SECRET, delete_mode="full"), {}
        )
        assert env["INTERVALS_ICU_DELETE_MODE"] == "full"

    def test_secret_mode_needs_api_key(self):
        with pytest.raises(run.AddonConfigError) as exc:
            run.build_environment(_opts(path_secret=SECRET), {})
        assert "api_key" in str(exc.value)

    def test_oauth_mode_maps_env(self):
        env = run.build_environment(
            _opts(
                oauth_client_id="id",
                oauth_client_secret="sec",
                public_base_url="https://intervals.example.com",
                allowed_athlete_ids="i1",
                scopes="ACTIVITY:READ",
            ),
            {},
        )
        assert env["INTERVALS_OAUTH_CLIENT_ID"] == "id"
        assert env["INTERVALS_OAUTH_CLIENT_SECRET"] == "sec"
        assert env["PUBLIC_BASE_URL"] == "https://intervals.example.com"
        assert env["ALLOWED_ATHLETE_IDS"] == "i1"
        assert env["OAUTH_SCOPES"] == "ACTIVITY:READ"

    @pytest.mark.parametrize(
        "missing", ["oauth_client_id", "oauth_client_secret", "public_base_url"]
    )
    def test_oauth_mode_incomplete(self, missing):
        values = {
            "oauth_client_id": "id",
            "oauth_client_secret": "sec",
            "public_base_url": "https://x.example",
        }
        values[missing] = ""
        with pytest.raises(run.AddonConfigError) as exc:
            run.build_environment(_opts(**values), {})
        assert missing in str(exc.value)
        assert "sec" not in str(exc.value).replace("oauth_client_secret", "")

    def test_empty_allowlist_warns_but_starts(self, capsys):
        run.build_environment(
            _opts(oauth_client_id="id", oauth_client_secret="sec", public_base_url="https://x.io"),
            {},
        )
        assert "allowed_athlete_ids is empty" in capsys.readouterr().err

    def test_stale_env_values_cannot_leak_in(self):
        env = run.build_environment(
            _opts(api_key="k", athlete_id="i1", path_secret=SECRET),
            {"INTERVALS_OAUTH_CLIENT_ID": "stale"},
        )
        assert "INTERVALS_OAUTH_CLIENT_ID" not in env

    def test_server_argv(self):
        argv = run.server_argv(_opts(log_level="debug"))
        assert argv[1:] == [
            "-m",
            "intervals_icu_mcp.server",
            "--transport",
            "http",
            "--host",
            "0.0.0.0",
            "--port",
            "8099",
            "--log-level",
            "debug",
        ]
        assert run.server_argv(_opts(log_level="bogus"))[-1] == "info"

    def test_describe_never_prints_values(self):
        line = run.describe(_opts(path_secret=SECRET, oauth_client_id="client-id-value"))
        assert SECRET not in line
        assert "client-id-value" not in line
        assert line == "modes=oauth,secret-path"

    def test_main_exits_cleanly_on_bad_config(self, tmp_path, monkeypatch, capsys):
        options = tmp_path / "options.json"
        options.write_text(json.dumps(_opts(api_key="secret-api-key-value")))
        monkeypatch.setattr(run, "OPTIONS_PATH", options)
        with pytest.raises(SystemExit) as exc:
            run.main()
        assert exc.value.code == 1
        assert "secret-api-key-value" not in capsys.readouterr().err

    def test_main_execs_server(self, tmp_path, monkeypatch):
        options = tmp_path / "options.json"
        options.write_text(json.dumps(_opts(api_key="k", athlete_id="i1", path_secret=SECRET)))
        monkeypatch.setattr(run, "OPTIONS_PATH", options)
        calls = []
        monkeypatch.setattr(run.os, "execvpe", lambda *a: calls.append(a))
        run.main()
        ((file, argv, env),) = calls
        assert file == sys.executable
        assert "intervals_icu_mcp.server" in argv
        assert env["MCP_PATH_SECRET"] == SECRET


class TestAddonFiles:
    def test_config_options_match_schema_and_launcher(self):
        config = yaml.safe_load((ADDON / "config.yaml").read_text())
        assert set(config["options"]) == set(config["schema"])
        assert set(config["options"]) == set(run.OPTION_ENV) | {"log_level"}
        for secret in ("api_key", "path_secret", "oauth_client_secret"):
            assert config["schema"][secret].startswith("password")
        assert config["arch"] == ["amd64", "aarch64"]
        # Not published on the host: the proxy uses the internal network.
        assert config["ports"] == {"8099/tcp": None}
        assert config["init"] is False
        assert config["image"] == "ghcr.io/bjorngadde/{arch}-ha-app-intervals-icu-mcp"
        for key in ("host_network", "hassio_api", "homeassistant_api", "ingress"):
            assert not config.get(key), key

    def test_dockerfile_pins_its_inputs(self):
        dockerfile = (ADDON / "Dockerfile").read_text()
        assert re.search(
            r"^FROM ghcr\.io/home-assistant/base-python:\S+@sha256:[0-9a-f]{64}$",
            dockerfile,
            re.MULTILINE,
        )
        assert re.search(r"^ARG INTERVALS_MCP_REF=[0-9a-f]{40}$", dockerfile, re.MULTILINE)
        assert 'CMD ["python3", "/run.py"]' in dockerfile
        assert "--frozen" in dockerfile  # dependencies come from uv.lock
        assert "HEALTHCHECK" in dockerfile

    def test_translations_cover_every_option(self):
        config = yaml.safe_load((ADDON / "config.yaml").read_text())
        translations = yaml.safe_load((ADDON / "translations" / "en.yaml").read_text())
        assert set(translations["configuration"]) == set(config["options"])

    def test_caddy_site_block(self):
        caddyfile = (REPO / "caddy" / "Caddyfile").read_text()
        site = caddyfile[caddyfile.index("intervals.gadde.nu {") :]
        site = site[: site.index("\n}\n")]
        for directive in (
            "import gadde_tls",
            "max_size 2MB",
            "reverse_proxy 38f2f41e-intervals-icu-mcp:8099",
            "flush_interval -1",
        ):
            assert directive in site, directive
        # Secret paths must never reach Caddy's log.
        assert "request>uri delete" in caddyfile

    def test_repository_manifest(self):
        manifest = yaml.safe_load((REPO / "repository.yaml").read_text())
        assert manifest["name"]
        assert manifest["url"] == "https://github.com/bjorngadde/home-assistant-apps"
