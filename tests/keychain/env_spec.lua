local env = require("keychain.env")

describe("keychain.env", function()
  describe("parse_line", function()
    it("parses blank lines", function()
      local entry = env.parse_line("", 1)
      assert.are.equal("blank", entry.kind)
    end)

    it("parses comment lines", function()
      local entry = env.parse_line("  # a comment", 1)
      assert.are.equal("comment", entry.kind)
    end)

    it("parses a simple key/value", function()
      local entry = env.parse_line("FOO=bar", 3)
      assert.are.equal("kv", entry.kind)
      assert.are.equal("FOO", entry.key)
      assert.are.equal("bar", entry.value)
      assert.is_nil(entry.quote)
      assert.is_false(entry.export)
    end)

    it("strips matching quotes", function()
      local dq = env.parse_line('FOO="bar baz"', 1)
      assert.are.equal("bar baz", dq.value)
      assert.are.equal('"', dq.quote)

      local sq = env.parse_line("FOO='bar baz'", 1)
      assert.are.equal("bar baz", sq.value)
      assert.are.equal("'", sq.quote)
    end)

    it("detects an `export` prefix", function()
      local entry = env.parse_line("export FOO=bar", 1)
      assert.is_true(entry.export)
      assert.are.equal("FOO", entry.key)
      assert.are.equal("bar", entry.value)
    end)

    it("detects a keychain:// reference (only when unquoted)", function()
      local ref = env.parse_line("API_KEY=keychain://API_KEY", 1)
      assert.are.equal("API_KEY", ref.ref_account)

      local quoted_ref = env.parse_line('API_KEY="keychain://API_KEY"', 1)
      assert.is_nil(quoted_ref.ref_account)
    end)
  end)

  describe("parse_ref / make_ref", function()
    it("round-trips an account name", function()
      local ref = env.make_ref("MY_ACCOUNT")
      assert.are.equal("keychain://MY_ACCOUNT", ref)
      assert.are.equal("MY_ACCOUNT", env.parse_ref(ref))
    end)

    it("returns nil for non-references", function()
      assert.is_nil(env.parse_ref("plain-value"))
      assert.is_nil(env.parse_ref("keychain://"))
    end)
  end)

  describe("render_entry / render_ref_line", function()
    it("preserves quote style", function()
      local entry = env.parse_line('FOO="bar baz"', 1)
      assert.are.equal('FOO="bar baz"', env.render_entry(entry))
    end)

    it("preserves export style", function()
      local entry = env.parse_line("export FOO=bar", 1)
      assert.are.equal("export FOO=bar", env.render_entry(entry))
    end)

    it("renders a reference line", function()
      assert.are.equal("API_KEY=keychain://API_KEY", env.render_ref_line("API_KEY", "API_KEY"))
      assert.are.equal(
        "export API_KEY=keychain://API_KEY",
        env.render_ref_line("API_KEY", "API_KEY", { export = true })
      )
    end)
  end)

  describe("resolve_entries", function()
    it("resolves refs and passes through plain values", function()
      local entries = env.parse_lines({
        "# comment",
        "",
        "DEBUG=true",
        "API_KEY=keychain://API_KEY",
      })

      local lines, errors = env.resolve_entries(entries, function(account)
        if account == "API_KEY" then
          return true, "s3cr3t-value"
        end
        return false, "not found"
      end)

      assert.are.same({
        "# comment",
        "",
        "DEBUG=true",
        "API_KEY=s3cr3t-value",
      }, lines)
      assert.are.same({}, errors)
    end)

    it("reports errors for unresolvable refs without raising", function()
      local entries = env.parse_lines({ "MISSING=keychain://MISSING" })

      local lines, errors = env.resolve_entries(entries, function()
        return false, "no entry found"
      end)

      assert.are.equal("no entry found", errors.MISSING)
      assert.truthy(lines[1]:match("^# keychain%.nvim: FAILED"))
    end)
  end)

  describe("resolve_values", function()
    it("resolves refs and passes through plain values as key/value pairs", function()
      local entries = env.parse_lines({
        "# comment",
        "",
        "DEBUG=true",
        "API_KEY=keychain://API_KEY",
      })

      local resolved, errors = env.resolve_values(entries, function(account)
        if account == "API_KEY" then
          return true, "s3cr3t-value"
        end
        return false, "not found"
      end)

      assert.are.same({
        { key = "DEBUG", value = "true" },
        { key = "API_KEY", value = "s3cr3t-value" },
      }, resolved)
      assert.are.same({}, errors)
    end)

    it("omits unresolvable refs from the result and reports the error", function()
      local entries = env.parse_lines({ "MISSING=keychain://MISSING" })

      local resolved, errors = env.resolve_values(entries, function()
        return false, "no entry found"
      end)

      assert.are.same({}, resolved)
      assert.are.equal("no entry found", errors.MISSING)
    end)
  end)

  describe("generated marker", function()
    it("recognizes its own marker as the first line", function()
      local marker = env.generated_marker()
      assert.is_true(env.has_generated_marker({ marker, "FOO=bar" }))
      assert.is_false(env.has_generated_marker({ "FOO=bar" }))
    end)
  end)

  describe("gitignore helpers", function()
    it("detects an already-ignored path", function()
      assert.is_true(env.is_gitignored({ "node_modules/", ".env.local" }, ".env.local"))
      assert.is_false(env.is_gitignored({ "node_modules/" }, ".env.local"))
    end)

    it("appends a new entry", function()
      local lines = env.add_to_gitignore({ "node_modules/" }, ".env.local")
      assert.are.same({ "node_modules/", "", ".env.local" }, lines)
    end)
  end)
end)
