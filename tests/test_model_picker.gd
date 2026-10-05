extends SceneTree
## Run: python scripts/godot_run.py --import -- --headless --script tests/test_model_picker.gd
## Which model suits which computer, and finding an installed model, without any model or download.

var failures := 0
const TMP := "user://test_models"


func check(condition: bool, label: String) -> void:
	if condition:
		print("ok    ", label)
	else:
		failures += 1
		print("FAIL  ", label)


func touch(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("x")
	f.close()


func _init() -> void:
	# The recommendation follows the measurements
	var rtx3070 := ModelPicker.recommend({"kind": "nvidia", "vram_mb": 8192, "ram_mb": 32000})
	check(rtx3070["id"] == "e4b" and rtx3070["meets_minimum"], "an 8 GB NVIDIA card (the test PC) gets the main model")
	check(ModelPicker.recommend({"kind": "nvidia", "vram_mb": 6144, "ram_mb": 16000})["id"] == "e4b", "6 GB of VRAM is enough for the main model")
	check(ModelPicker.recommend({"kind": "nvidia", "vram_mb": 5999, "ram_mb": 16000})["id"] == "e2b", "just under 6 GB gets the small model")
	check(ModelPicker.recommend({"kind": "nvidia", "vram_mb": 4096, "ram_mb": 16000})["id"] == "e2b", "a 4 GB card gets the small model")
	var tiny_gpu := ModelPicker.recommend({"kind": "nvidia", "vram_mb": 2048, "ram_mb": 16000})
	check(tiny_gpu["id"] == "e2b" and tiny_gpu["reason"].contains("processor"), "a 2 GB card gets the small model and is told it runs on the processor")
	check(ModelPicker.recommend({"kind": "apple", "ram_mb": 16000})["id"] == "e4b", "a Mac with 16 GB gets the main model")
	check(ModelPicker.recommend({"kind": "apple", "ram_mb": 8000})["id"] == "e2b", "a Mac with 8 GB gets the small model")
	check(ModelPicker.recommend({"kind": "apple", "ram_mb": 16000})["reason"].contains("not measured"), "the Mac advice says it was not measured")
	var unknown := ModelPicker.recommend({"kind": "other", "vram_mb": -1, "ram_mb": 32000})
	check(unknown["id"] == "e2b" and unknown["reason"].contains("safe choice"), "an unrecognised graphics card gets the safe small model")
	var low_ram := ModelPicker.recommend({"kind": "other", "ram_mb": 4000})
	check(low_ram["id"] == "e2b" and not low_ram["meets_minimum"] and low_ram["reason"].contains("less than 6 GB"), "under 6 GB of RAM is flagged")
	check(ModelPicker.recommend({})["id"] == "e2b", "nothing known gives the small model, not an error")
	for id in ModelPicker.MODELS:
		var m: Dictionary = ModelPicker.MODELS[id]
		check(m["hf"].begins_with("hf:") and m["file"].ends_with(".gguf") and m["size_gb"] > 1.0, "catalog entry %s is complete" % id)

	# detect() on this machine returns something usable
	var hw := ModelPicker.detect()
	check(hw["ram_mb"] > 0 and hw["kind"] in ["nvidia", "apple", "other"] and hw["os"] != "", "detect() describes this computer: %s" % str(hw))
	check(ModelPicker.recommend(hw)["id"] in ["e4b", "e2b"], "and the recommendation for it is a known model (%s)" % ModelPicker.recommend(hw)["id"])

	# Finding installed models
	var dir_a := TMP + "/a"
	var dir_b := TMP + "/b"
	var settings := TMP + "/settings.cfg"
	for d in [dir_a, dir_b]:
		DirAccess.make_dir_recursive_absolute(d)
		for f in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(String(d).path_join(f))
	DirAccess.remove_absolute(settings)
	check(ModelPicker.installed_path("e4b", [dir_a, dir_b], settings) == "", "nothing installed gives an empty path")
	check(ModelPicker.best_installed("e4b", [dir_a, dir_b], settings).is_empty(), "and no best model")
	touch(dir_b + "/gemma-4-E2B-it-Q4_K_M.gguf")
	check(ModelPicker.installed_path("e2b", [dir_a, dir_b], settings).ends_with("gemma-4-E2B-it-Q4_K_M.gguf"), "an installed model is found in the second folder")
	var best := ModelPicker.best_installed("e4b", [dir_a, dir_b], settings)
	check(best.get("id") == "e2b", "the recommended one is missing, so the other installed one is used")
	touch(dir_a + "/gemma-4-E4B-it-Q4_K_M.gguf")
	check(ModelPicker.best_installed("e4b", [dir_a, dir_b], settings).get("id") == "e4b", "the recommended one wins when both are installed")
	check(ModelPicker.best_installed("e2b", [dir_a, dir_b], settings).get("id") == "e2b", "and the other way round")
	var fallback_dir := TMP + "/c"
	DirAccess.make_dir_recursive_absolute(fallback_dir)
	for f in DirAccess.get_files_at(fallback_dir):
		DirAccess.remove_absolute(fallback_dir.path_join(f))
	touch(fallback_dir + "/Qwen_Qwen3.5-4B-Q4_K_M-vendor-sampling.gguf")
	check(ModelPicker.best_installed("e4b", [fallback_dir], settings).get("id") == "fallback", "a known fallback model is used when no Gemma is installed")

	# Remembering a download
	var elsewhere := TMP + "/cache/gemma-4-E4B-it-Q4_K_M.gguf"
	touch(elsewhere)
	ModelPicker.remember("e4b", ProjectSettings.globalize_path(elsewhere), settings)
	check(ModelPicker.remembered_path("e4b", settings) == ProjectSettings.globalize_path(elsewhere), "a remembered download is read back")
	check(ModelPicker.installed_path("e4b", [], settings) == ProjectSettings.globalize_path(elsewhere), "and found even when it is in no model folder")
	DirAccess.remove_absolute(elsewhere)
	check(ModelPicker.installed_path("e4b", [], settings) == "", "a remembered file that has since been deleted is not 'installed'")
	check(ModelPicker.remembered_path("e4b", TMP + "/no_such.cfg") == "", "no settings file gives an empty path")
	var broken := FileAccess.open(TMP + "/broken.cfg", FileAccess.WRITE)
	broken.store_string("[models\ne4b = ")
	broken.close()
	check(ModelPicker.remembered_path("e4b", TMP + "/broken.cfg") == "", "a damaged settings file does not crash")

	print("\n%s" % ("ALL PASSED" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)
