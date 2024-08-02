local lib = require("neotest.lib")
local types = require("neotest.types")
local logger = require("neotest.logging")
local xml2lua = require("neotest-java.xml2lua.xml2lua")
local handler = require("neotest-java.xml2lua.xmlhandler.tree")

---@param dir_path string
---@return table<table>
local function parse_xml(dir_path)
	local parser = xml2lua.parser(handler)

	local files = lib.files.find(dir_path, {
		filter_dir = function(filename)
			logger.debug("Result filename ", filename)
			if filename:find("%.xml") then
				return true
			end
			return false
		end,
	})

	return vim.tbl_map(function(file_path)
		local file_contents = lib.files.read(file_path)
		parser:parse(file_contents)
		return handler.root
	end, files)
end

local function get_position_for_test_case(tree, test_case)
	local function_name = test_case:gsub("%(%)", "")

	for _, position in tree:iter() do
		if position.name == function_name then
			return position
		end
	end
end

---@param build_spec neotest.RunSpec
---@param _ neotest.StrategyResult
---@param tree neotest.Tree
---@return table<string, neotest.Result>
return function(build_spec, _, tree)
	local results = {}
	local gradle_test_reports = parse_xml(build_spec.context.test_results_dir)

	for _, report in pairs(gradle_test_reports) do
		for _, test_case in pairs((report.testsuite or {}).testcase) do
			local position = get_position_for_test_case(tree, test_case._attr.name)
			if position ~= nil then
				results[position.id] = {
					status = test_case.failure == nil and types.ResultStatus.passed or types.ResultStatus.failed,
					short = test_case.failure,
					errors = { message = test_case.failure },
				}
			else
				logger.warn("Test case does not have correspoding position: ", test_case)
			end
		end
	end

	return results
end
