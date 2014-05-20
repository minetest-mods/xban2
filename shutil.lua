
shutil = { }

function shutil.copy_file(src, dst)
	local e, sf, df, cont, ok
	sf, e = io.open(src, "rb")
	if not sf then
		return nil, "Error opening input: "..(e or "")
	end
	df, e = io.open(dst, "wb")
	if not df then
		sf:close()
		return nil, "Error opening output: "..(e or "")
	end
	cont, e = sf:read("*a")
	if not cont then
		sf:close()
		df:close()
		return nil, "Error reading input: "..(e or "")
	end
	ok, e = df:write(cont)
	if not ok then
		sf:close()
		df:close()
		return nil, "Error writing output: "..(e or "")
	end
	sf:close()
	df:close()
	return true
end

function shutil.move_file(src, dst)
	local ok, e = shutil.copy_file(src, dst)
	if not ok then
		return nil, "Copy failed: "..(e or "")
	end
	ok, e = os.remove(src)
	if not ok then
		return nil, "Remove failed: "..(e or "")
	end
	return true
end
