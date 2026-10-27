E.host.register(function(dt, events)
	local ok, err = pcall(E.step, dt, events)
	if not ok then
		E.host.error("engine step failed: " .. tostring(err), debug.traceback())
	end
	return 0
end, function(source, chunkname)
	return E.run(source, chunkname)
end)
