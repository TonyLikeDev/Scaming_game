class_name SysStats
extends RefCounted
## Process RAM and GPU memory readings for the model tests. Everything shells out, so call it between
## measurements, never inside a timed section.


## Resident memory of this process in MB, or -1.0 when it cannot be read. Native memory (the model) counts.
static func process_ram_mb() -> float:
	var out: Array = []
	var pid := OS.get_process_id()
	match OS.get_name():
		"Windows":
			var code := OS.execute("powershell", ["-NoProfile", "-Command", "(Get-Process -Id %d).WorkingSet64" % pid], out)
			if code == 0 and out.size() > 0 and str(out[0]).strip_edges().is_valid_int():
				return float(str(out[0]).strip_edges()) / 1048576.0
		"macOS", "Linux":
			var code := OS.execute("ps", ["-o", "rss=", "-p", str(pid)], out)
			if code == 0 and out.size() > 0 and str(out[0]).strip_edges().is_valid_int():
				return float(str(out[0]).strip_edges()) / 1024.0
	return -1.0


## Total GPU memory in use across all processes, in MiB, via nvidia-smi (per-process numbers are not
## available on Windows). Returns -1.0 without an NVIDIA GPU. On Apple silicon memory is shared, so use RAM.
static func gpu_used_mb() -> float:
	var out: Array = []
	var code := OS.execute("nvidia-smi", ["--query-gpu=memory.used", "--format=csv,noheader,nounits"], out)
	if code == 0 and out.size() > 0 and str(out[0]).strip_edges().is_valid_int():
		return float(str(out[0]).strip_edges())
	return -1.0


static func gpu_total_mb() -> float:
	var out: Array = []
	var code := OS.execute("nvidia-smi", ["--query-gpu=memory.total", "--format=csv,noheader,nounits"], out)
	if code == 0 and out.size() > 0 and str(out[0]).strip_edges().is_valid_int():
		return float(str(out[0]).strip_edges())
	return -1.0
