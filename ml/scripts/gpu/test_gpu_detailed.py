import tensorflow as tf
import os

print("="*80)
print("TensorFlow GPU Detection Test")
print("="*80)

# Basic info
print(f"\nTensorFlow version: {tf.__version__}")
print(f"CUDA built: {tf.test.is_built_with_cuda()}")

# Check environment variables
print(f"\nEnvironment Variables:")
print(f"  CUDA_PATH: {os.environ.get('CUDA_PATH', 'Not set')}")
print(f"  Path contains CUDA: {'cuda' in os.environ.get('PATH', '').lower()}")

# List all devices
print(f"\nAll Physical Devices:")
for device in tf.config.list_physical_devices():
    print(f"  - {device.device_type}: {device.name}")

# Check GPU specifically
gpus = tf.config.list_physical_devices('GPU')
print(f"\nGPU Devices Found: {len(gpus)}")

if gpus:
    print("\n✅ GPU DETECTED!")
    for i, gpu in enumerate(gpus):
        print(f"\n  GPU {i}:")
        print(f"    Name: {gpu.name}")
        
        # Try to get device details
        try:
            details = tf.config.experimental.get_device_details(gpu)
            if details:
                print(f"    Device: {details.get('device_name', 'Unknown')}")
                print(f"    Compute Capability: {details.get('compute_capability', 'Unknown')}")
        except:
            print(f"    Details: Not available")
    
    # Test GPU computation
    print("\n  Testing GPU computation...")
    try:
        with tf.device('/GPU:0'):
            a = tf.random.normal([1000, 1000])
            b = tf.random.normal([1000, 1000])
            c = tf.matmul(a, b)
            result = c.numpy()
        print("  ✅ GPU computation successful!")
    except Exception as e:
        print(f"  ❌ GPU computation failed: {e}")
        
else:
    print("\n❌ NO GPU DETECTED")
    print("\nTroubleshooting steps:")
    print("  1. Verify CUDA installation: nvcc --version")
    print("  2. Verify NVIDIA driver: nvidia-smi")
    print("  3. Check cuDNN files are copied correctly")
    print("  4. Restart your computer")
    print("  5. Reinstall TensorFlow: pip install --upgrade tensorflow")

print("\n" + "="*80)