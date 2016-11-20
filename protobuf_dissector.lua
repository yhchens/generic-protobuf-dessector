protobuf_proto = Proto("protobuf", "Google Proto Buffers")

local function vaildate_utf8(string_buf)
	local i = 0

	while i < string_buf:len() do
		if 0 == bit32.band(string_buf(i, 1):uint(), 0x80) then
			i = i + 1
		else
			local byte_len = 0

			if 0x06 == bit32.rshift(string_buf(i, 1):uint(), 5) then
				byte_len = 1
			elseif 0x0e == bit32.rshift(string_buf(i, 1):uint(), 4) then
				byte_len = 2
			elseif 0x1e == bit32.rshift(string_buf(i, 1):uint(), 3) then
				byte_len = 3
			elseif 0x3e == bit32.rshift(string_buf(i, 1):uint(), 2) then
				byte_len = 4
			elseif 0x7e == bit32.rshift(string_buf(i, 1):uint(), 1) then
				byte_len = 5
			else
				return nil
			end

			for j = 1, byte_len do
				if 0x02 ~= bit32.rshift(string_buf(i + j, 1):uint(), 6) then
					return nil
				end
			end

			i = i + 1 + byte_len
		end
	end

	return true
end

local function protobuf_signed_varint(val)
	if 0x01 == val then
		return nil
	elseif  0x01 == bit32.band(val, 0x01) then
		return - bit32.rshift(val, 1)
	else
		return bit32.rshift(val, 1)
	end
end

local function protobuf_varint(buf)
	local i = 0
	local val = 0
	local flag = false

	while i < buf:len() do
		val = val + bit32.lshift(bit32.band(buf(i, 1):uint(), 0x7f), 7 * i)

		if buf(i, 1):uint() < 0x80 then
			flag = true
			break
		end

		i = i + 1
	end

	if flag then
		return val, i + 1
	end

	return nil, 0
end

local function protobuf_key(key_buf)
	local s_type, len = protobuf_varint(key_buf)
	local wire_t = bit32.band(s_type, 0x07)
	local field_n = bit32.rshift(s_type, 3)
	
	return field_n, wire_t, len
end

local function protobuf_packed_values_tree(buf, tree)
	if buf:len() % 4 == 0 then
		local packed_tree = tree:add(buf, "Packed fixed32 values: ")
		local i = 0
		local display_index = 0
		local type_tree = packed_tree:add(buf, "unsigned:")

		while i < buf:len() do
			type_tree:add(buf(i, 4), "[" .. display_index .. ']: ' .. buf(i, 4):le_uint())
			i = i + 4
			display_index = display_index + 1
		end
		
		i = 0
		display_index = 0
		type_tree = packed_tree:add(buf, "signed:")

		while i < buf:len() do
			type_tree:add(buf(i, 4), "[" .. display_index .. ']: ' .. buf(i, 4):le_int())
			i = i + 4
			display_index = display_index + 1
		end

		i = 0
		display_index = 0
		type_tree = packed_tree:add(buf, "float:")

		while i < buf:len() do
			type_tree:add(buf(i, 4), "[" .. display_index .. ']: ' .. buf(i, 4):le_float())
			i = i + 4
			display_index = display_index + 1
		end

		if 0 == buf:len() % 8 then
			packed_tree = tree:add(buf, "Packed fixed64 values: ")

			i = 0
			display_index = 0
			type_tree = packed_tree:add("unsigned:")

			while i < buf:len() do
				type_tree:add(buf(i, 8), "[" .. display_index .. "]: " .. buf(i, 8):le_uint64())
				i = i + 8
				display_index = display_index + 1
			end

			i = 0
			display_index = 0
			type_tree = packed_tree:add("signed:")

			while i < buf:len() do
				type_tree:add(buf(i, 8), "[" .. display_index .. "]: " .. buf(i, 8):le_int64())
				i = i + 8
				display_index = display_index + 1
			end

			i = 0
			display_index = 0
			type_tree = packed_tree:add("double:")

			while i < buf:len() do
				type_tree:add(buf(i, 8), "[" .. display_index .. "]: " .. buf(i, 8):le_float())
				i = i + 8
				display_index = display_index + 1
			end
		end
	end

	local i = 0
	local signed_flag = true
	while i < buf:len() do
		local val, len = protobuf_varint(buf(i, buf:len() - i))
		
		if 0 == len then
			return nil
		end

		if nil == protobuf_signed_varint(val) then
			signed_flag = false
		end
		
		i = i + len
	end
	local packed_tree = tree:add(buf, "Packed varint values: ")
	local type_tree = packed_tree:add(buf, "unsigned:")
	local display_index = 0
	i = 0

	while i < buf:len() do
		local val, len = protobuf_varint(buf(i, buf:len() - i))
		type_tree:add(buf(i, len), "[" .. display_index .. "]: " .. val)

		i = i + len
		display_index = display_index + 1
	end

	if signed_flag then
		type_tree = packed_tree:add(buf, "signed:")
		i = 0
		display_index = 0

		while i < buf:len() do
			local val, len = protobuf_varint(buf(i, buf:len() - i))
			type_tree:add(buf(i, len), "[" .. display_index .. "]: " .. protobuf_signed_varint(val))

			i = i + len
			display_index = display_index + 1
		end
	end

	return true
end

local function protobuf_vaildate_message(buf)
	local i = 0

	if buf:len() < 1 then
		return false
	end

	while i < buf:len() do
		local field_n, wire_t, key_len = protobuf_key(buf(i, buf:len() - i))
		
		if 0 == wire_t then
			if buf:len() - (i +  key_len) <= 0 then
				return false
			end

			local val, len = protobuf_varint(buf(i + 1, buf:len() - (i + 1)))
			i = i + len + key_len
		elseif 1 == wire_t then
			if i + key_len + 8 > buf:len() then
				return false
			end

			i = i + key_len + 8
		elseif 2 == wire_t then
			if buf:len() - (i + key_len) <= 0 then
				return false
			end

			local val, len = protobuf_varint(buf(i + key_len, buf:len() - (i + key_len)))
			
			if i + len + val > buf:len() then
				return false
			end

			i = i + len + val + key_len
		elseif 5 == wire_t then
			if i + key_len + 4 > buf:len() then
				return false
			end

			i = i + key_len + 4
		else
			return false
		end
	end

	return true
end

local function protobuf_tree(buf, otree)
	local i = 0

	if false == protobuf_vaildate_message(buf) then
		return nil
	end

	local tree = otree:add(buf(), "Proto Bufffers Message: ")

	while i < buf:len() do
		local field_n, wire_t, key_len = protobuf_key(buf(i, buf:len() - i))

		if 0 == wire_t then
			local val, len = protobuf_varint(buf(i + key_len,buf:len() - (i + key_len)))
			local varint_tree = tree:add(buf(i, key_len + len), "[" .. field_n .. "] varint: ")
			
			varint_tree:add(buf(i, key_len), "Field number: " .. field_n .. "    Wire type: " .. wire_t .. " (varint)")
			varint_tree:add(buf(i + key_len, len), "unsigned: " .. val)
			if protobuf_signed_varint(val) ~= nil then
				varint_tree:add(buf(i + key_len, len), "signed: " .. protobuf_signed_varint(val))
			end

			i = i + len + key_len
		elseif 1 == wire_t then
			local fix64_tree = tree:add(buf(i, key_len + 8), "[" .. field_n .. "] 64bit: ")
			
			fix64_tree:add(buf(i, key_len), "Field number: " .. field_n .. "    Wire type: " .. wire_t .. " (64bit)")
			fix64_tree:add(buf(i + key_len, 8), "fix64: " .. buf(i + key_len, 8):le_uint64())
			fix64_tree:add(buf(i + key_len, 8), "sfix64: " .. buf(i + key_len, 8):le_int64())
			fix64_tree:add(buf(i + key_len, 8), "double: " .. buf(i + key_len, 8):le_float())

			i = i + key_len + 8
		elseif 2 == wire_t then
			local val, len = protobuf_varint(buf(i + 1, buf:len() - (i + key_len)))
			local ld_tree = tree:add(buf(i, len + val + key_len), "[" .. field_n .. "] length-delimited (" .. val .. " bytes): ")
			
			ld_tree:add(buf(i, key_len), "Field number: " .. field_n .. "    Wire type: " .. wire_t .. " (length-delimited)")
			ld_tree:add(buf(i + key_len, len), "Length: " .. val)
			
			if val > 0 then
				if vaildate_utf8(buf(i + key_len + len, val)) then
					local str_tree = ld_tree:add(buf(i + key_len + len, val), "String: ")
					str_tree:add(buf(i + key_len + len, val), buf(i + key_len + len, val):string())
				end

				protobuf_tree(buf(i + key_len + len, val), ld_tree)
				protobuf_packed_values_tree(buf(i + key_len  + len, val), ld_tree)
			end
			
			i = i + len + val + 1
		elseif 5 == wire_t then
			local fix32_tree = tree:add(buf(i, key_len + 4), "[" .. field_n .. "] 32bit: ")
			
			fix32_tree:add(buf(i, key_len), "Field number: " .. field_n .. "    Wire type: " .. wire_t .. " (32bit")
			fix32_tree:add(buf(i + key_len, 4), "fix32: " .. buf(i + key_len, 4):le_uint64())
			fix32_tree:add(buf(i + key_len, 4), "sfix32: " .. buf(i + key_len, 4):le_int64())
			fix32_tree:add(buf(i + key_len, 4), "float: " .. buf(i + key_len, 4):le_float())
			
			i = i + key_len + 4
		end
	end

	return true
end

function protobuf_proto.dissector(buf,pinfo,tree)
	protobuf_tree(buf, tree)
end

local udp_table = DissectorTable.get("udp.port")
udp_table:add(60002, protobuf_proto)
