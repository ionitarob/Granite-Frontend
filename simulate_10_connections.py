import time

# Real data fetched from the Engine API
CHANNELS = [
    {"image_id": "greenpower-hp-prossff-400-g9", "size_gb": 3.77},
    {"image_id": "kitdigital-acer-travelmate-p2-14", "size_gb": 11.21},
    {"image_id": "kitdigital-acer-travelmate-p2-16", "size_gb": 11.25},
    {"image_id": "kitdigital-hp-aio-proone-440-g9", "size_gb": 10.35},
    {"image_id": "kitdigital-hp-elitebook-640-g11-cifrado", "size_gb": 11.41},
    {"image_id": "kitdigital-hp-elitebook-665-g11", "size_gb": 10.96},
    {"image_id": "kitdigital-hp-elitebook-845-g11", "size_gb": 10.71},
    {"image_id": "kitdigital-hp-elitebook-865-g11", "size_gb": 10.74},
    {"image_id": "kitdigital-hp-probook-440-g11", "size_gb": 11.3},
    {"image_id": "kitdigital-hp-probook-460-g11", "size_gb": 11.62},
]

GLOBAL_MAX_MBPS = 8000.0
STREAM_MAX_MBPS = 850.0 # From image/governor logic

def simulate_real():
    print("🚀 Sentinel Multicast Unified Engine Starting...")
    time.sleep(0.3)
    print("✅ Unified Engine READY on 10.20.31.10:8000")
    print(f"[Governor] Global Capacity: {GLOBAL_MAX_MBPS} Mbps")
    print("-" * 50)

    total_time_needed = 0
    
    for i, chan in enumerate(CHANNELS, 1):
        image_id = chan["image_id"]
        size_gb = chan["size_gb"]
        
        # Fair share speed
        speed = min(GLOBAL_MAX_MBPS / i, STREAM_MAX_MBPS)
        
        print(f"[Controller] Starting stream {i}: {image_id}")
        print(f"[Governor] Recalculating: {i} streams -> {speed:.2f} Mbps")
        
        # Precise calculation
        size_bits = size_gb * 1024 * 1024 * 1024 * 8
        seconds = size_bits / (speed * 1_000_000)
        minutes = int(seconds // 60)
        rem_seconds = seconds % 60
        
        print(f"[{image_id}] Real Size: {size_gb} GB -> ETA: {minutes}m {rem_seconds:.1f}s")
        print("-" * 50)
        
        if i == 10:
            total_time_needed = seconds

    print(f"\n🏁 ALL 10 STREAMS STARTED (Parallel Operation)")
    print(f"Total simulated time for completion: {int(total_time_needed // 60)}m {total_time_needed % 60:.1f}s")

if __name__ == "__main__":
    simulate_real()
