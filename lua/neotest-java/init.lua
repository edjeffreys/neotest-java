local lib = require("neotest.lib")
local utils = require("neotest.utils")
local logger = require("neotest.logging")
local gradle_results = require("neotest-java.collect_gradle_results")

---@type neotest.Adapter
local JavaNeotestAdapter = { name = "neotest-java" }

local gradle = vim.fs.find({ "gradlew", "gradle" }, { upward = true })[1]
logger.debug("Java executable: ", gradle)
local projectRoot = vim.fs.dirname(vim.fs.find({ "build.gradle", "build.gradle.kts" }, { upward = true })[1])

local function match_root_pattern(...)
	local patterns = utils.tbl_flatten({ ... })
	return function(start_path)
		return vim.fs.dirname(vim.fs.find(patterns, { upward = true, path = start_path })[1])
	end
end

JavaNeotestAdapter.root = match_root_pattern("build.gradle", "build.gradle.kts")

function JavaNeotestAdapter.is_test_file(file_path)
	return vim.endswith(file_path, "Test.java")
end

function JavaNeotestAdapter.filter_dir(name, rel_path, root)
	return true
end

---@return neotest.Tree | nil
function JavaNeotestAdapter.discover_positions(path)
	local query = [[
  ;; test class
  (
    (class_declaration name: (identifier) @file.name)
    (#match? @file.name ".*Test$")
  ) @file.definition

  ;; test methods
  (
    (method_declaration
      (modifiers (marker_annotation name: (identifier) @test_annotation))
      name: (identifier) @test.name)
    (#match? @test_annotation ".*Test$")
  ) @test.definition
  ]]
	return lib.treesitter.parse_positions(path, query, { nested_namespaces = true })
end

local function get_test_results_dir()
	local command = {
		gradle,
		"--project-dir",
		projectRoot,
		"properties",
		"--property",
		"testResultsDir",
	}
	local _, output = lib.process.run(command, { stdout = true })
	local output_lines = vim.split(output.stdout or "", "\n")

	for _, line in pairs(output_lines) do
		if line:match("testResultsDir: ") then
			return line:gsub("testResultsDir: ", "") .. lib.files.sep .. "test"
		end
	end

	return ""
end

---@param args neotest.RunArgs
---@return neotest.RunSpec | nil
function JavaNeotestAdapter.build_spec(args)
	local position = args.tree:data()
	if position == nil then
		return
	end

	logger.debug("Position ID: ", position.id)
	logger.debug("Position Name: ", position.name)
	logger.debug("Position Type: ", position.type)

	local testArgs
	if position.type == "test" then
		testArgs = position.id:match("%a+%.java"):gsub("%.java", "") .. "." .. position.name
	elseif position.type == "file" then
		testArgs = position.name:gsub("%.java", "")
	end

	local command = table.concat({
		gradle,
		"--project-dir",
		projectRoot,
		"test",
		"--tests",
		"'" .. testArgs .. "'",
		"|| true",
	}, " ")

	local context = {}
	context.test_results_dir = get_test_results_dir()

	return { command = command, context = context }
end

---@param spec neotest.RunSpec
---@param _ neotest.StrategyResult
---@param tree neotest.Tree
---@return table<string, neotest.Result>
function JavaNeotestAdapter.results(spec, _, tree)
	return gradle_results(spec, _, tree)
end

return JavaNeotestAdapter
