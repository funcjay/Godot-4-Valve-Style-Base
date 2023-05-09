#
#	Generic sound manager object
#
#	Handles choosing and playing sounds through a desired player.
#	Reads entries from the "soundlist.json" file.
#

extends Node


var file := "res://soundlist.json"
var raw : String = FileAccess.get_file_as_string(file)
var dict : Dictionary = JSON.parse_string(raw)


## get_sounds(group, sound)
## Returns an array of files (and their playback parameters) from the specified group/sound combo.
func get_sounds(group: String, sound: String) -> Array:
	var groups : Array = dict.get("groups")
	
	var found_group := ""
	var found_sounds := Array()
	
	var temp_vol : float = 0
	var temp_pitch : float = 1
	
	# This shit is really evil but it works :>
	for grp in groups:
		if grp.name == group:
			found_group = grp.name
			
			# set group params first
			temp_vol = grp.get("vol", 0)
			temp_pitch = grp.get("pitch", 1)
			
			for snd in grp.sounds:
				if snd.name == sound:
					for f in snd.files:
						# if sound params are set, they take priority over group params
						if snd.get("vol"):
							temp_vol = snd.get("vol", 0)
						if snd.get("pitch"):
							temp_pitch = snd.get("pitch", 1)
						
						var fin := Array()
						
						fin.append(f)
						fin.append(temp_vol)
						fin.append(temp_pitch)
						
						found_sounds.append(fin)
					break	# we got the right sound, stop searching
			break	# we got the right group, stop searching
	
	if found_group == "":
		printerr("SoundManager (get_sounds): Couldn't find group ", group, "!")
	elif found_sounds == []:
		printerr("SoundManager (get_sounds): Got an empty sound list!")
	
	return found_sounds

## get_sound(group, sound, n)
## Returns a random file (and it's playback parameters) from the specified group/sound combo.
## If `n` is 0 or higher, returns the file at that specific index in the sound's "files" list.
func get_sound(group: String, sound: String, n: int = -1) -> Array:
	var got := get_sounds(group, sound)
	if got.is_empty():
		printerr("SoundManager (get_random): Trying to pick a random sound from an empty list!")
		return Array()
	
	if n < 0:
		return got.pick_random()
	else:
		return got[n]

## play_sound(player, group, sound, n, vol, pitch)
## Plays a sound through the specified AudioStreamPlayer node.
## Optionally allows modifying the volume and pitch defined in the soundlist file.
func play_sound(player, group: String, sound: String, n: int = -1, vol: float = 0, pitch: float = 1) -> void:
	if not player is AudioStreamPlayer and not player is AudioStreamPlayer2D and not player is AudioStreamPlayer3D:
		printerr("SoundManager (play_sound): Provided player is not an AudioStreamPlayer!")
		return
	
	var got := get_sound(group, sound, n)
	if got.is_empty():
		printerr("SoundManager (play_sound): Got an empty random sound!")
		return
	var got_file : String = got[0]
	var got_vol : float = got[1] + vol
	var got_pitch : float = got[2] * pitch
	
	got_vol = clamp(got_vol, -50, 50)
	got_pitch = clamp(got_pitch, 0.1, 5)
	
	if got_file == "" or not FileAccess.file_exists(got_file):
		printerr("SoundManager (play_sound): Trying to play non-existent sound ", got_file, "!")
		return

	player.set_stream(load(got_file))
	player.set_volume_db(got_vol)
	player.set_pitch_scale(got_pitch)
	player.play()
