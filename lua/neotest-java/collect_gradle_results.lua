local lib = require("neotest.lib")
local types = require("neotest.types")
local logger = require("neotest.logging")
local xml2lua = require("neotest-java.xml2lua.xml2lua")
local handler = require("neotest-java.xml2lua.xmlhandler.tree")

local function get_position_for_test_case(tree, test_case)
	local function_name = test_case:gsub("%(%)", "")

	for _, position in tree:iter() do
		if position.name == function_name then
			return position
		end
	end
end

local function get_position_result(tree, test_case)
	local position = get_position_for_test_case(tree, test_case._attr.name)
	if position ~= nil then
		return {
			position = position.id,
			result = {
				status = test_case.failure == nil and types.ResultStatus.passed or types.ResultStatus.failed,
				short = test_case.failure,
				errors = { message = test_case.failure },
			},
		}
	else
		logger.warn("Test case does not have correspoding position: ", test_case)
	end
end

---@param build_spec neotest.RunSpec
---@param _ neotest.StrategyResult
---@param tree neotest.Tree
---@return table<string, neotest.Result>
return function(build_spec, _, tree)
	local results = {}

	local files = lib.files.find(build_spec.context.test_results_dir, {
		filter_dir = function(filename)
			logger.debug("Result filename ", filename)
			if filename:find("%.xml") then
				return true
			end
			return false
		end,
	})

	for _, file_path in pairs(files) do
		local file_contents = lib.files.read(file_path)

		local xml = handler:new()
		local parser = xml2lua.parser(xml)
		parser:parse(file_contents)

		for i, test_case in pairs(xml.root.testsuite) do
			if i == "testcase" then
				if test_case._attr ~= nil then
					local result = get_position_result(tree, test_case)
					if result ~= nil then
						results[result.position] = result.result
					end
				else
					for _, test in pairs(test_case) do
						local result = get_position_result(tree, test)
						if result ~= nil then
							results[result.position] = result.result
						end
					end
				end
			end
		end
	end

	return results
end
