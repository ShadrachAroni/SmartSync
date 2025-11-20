````md
# Usage Notes

### **1. First Run**
Run the training script normally:
```bash
cd ml && python scripts/train_smart_home.py
````

Tensors and the scaler will be cached automatically.

---

### **2. Resume After Crash or Pause**

Use the `--resume` flag:

```bash
python scripts/train_smart_home.py --resume
```

The script will automatically reload:

* `cache/dataset_<hash>.npz`
* `preprocessor_<hash>.joblib`
* `checkpoints/<hash>_latest.weights.h5`

Training continues from the last recorded epoch.

---

### **3. Safe Pause During Training**

In another terminal:

```bash
python scripts/train_smart_home.py --request-pause
```

The main training process will:

1. Finish the current epoch
2. Save state as **paused**
3. Exit cleanly

Resume later with:

```bash
python scripts/train_smart_home.py --resume
```

If you manually removed the pause flag, clear the state:

```bash
python scripts/train_smart_home.py --clear-pause
```

---

### **4. Start Over (Fresh Training)**

Wipe cached datasets + checkpoints:

```bash
python scripts/train_smart_home.py --reset-cache
```

Rebuild features (also clears state) without manual cleanup:

```bash
python scripts/train_smart_home.py --refresh-data
```

---

### **5. Pause/State Metadata**

State information is stored in:

```
models/saved_models/artifacts/cache/state_<hash>.json
```

Inspecting this file reveals:

* Last completed epoch
* Training status
* Latest logs

---

### **6. GPU Memory Management**

The script automatically sets:

```
TF_GPU_ALLOCATOR=cuda_malloc_async
```

This is done **before TensorFlow initializes**, so no extra environment configuration is needed.
You can still override it manually if desired.
