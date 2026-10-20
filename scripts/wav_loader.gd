
static func load_file(path: String) -> AudioStreamWAV:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	var channels := bytes.decode_u16(22)
	var rate := bytes.decode_u32(24)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = channels == 2
	stream.mix_rate = rate
	stream.data = bytes.slice(44)
	return stream
