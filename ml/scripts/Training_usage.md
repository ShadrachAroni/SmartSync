# Usage Notes

### **1. First Run**
Run the training script normally:
```bash
cd ml && python scripts/train_smart_home.py
```

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

### **4. Continuous/Incremental Training**

Load a previously saved model and continue training from epoch 0 with learned weights:

```bash
python scripts/train_smart_home.py --load-model
```

**Use cases:**
- Train the model multiple times, each run building upon previous learning
- Improve model performance with additional training epochs
- Fine-tune the model with new data while preserving previous knowledge

**How it works:**
1. Loads the saved model from `models/saved_models/schedule_predictor_v2/`
2. Validates model compatibility with current data shape
3. Starts training from epoch 0 but uses the learned weights from previous training
4. Saves the improved model back to the same location

**Example workflow:**
```bash
# First training run
python scripts/train_smart_home.py

# Second run: Continue learning
python scripts/train_smart_home.py --load-model

# Third run: Continue learning more
python scripts/train_smart_home.py --load-model
```

**Note:** The model starts from epoch 0 but retains all learned weights from previous training. Each run trains for the full number of epochs specified in config.

---

### **5. Start Over (Fresh Training)**

Wipe cached datasets + checkpoints:

```bash
python scripts/train_smart_home.py --reset-cache
```

Rebuild features (also clears state) without manual cleanup:

```bash
python scripts/train_smart_home.py --refresh-data
```

---

### **6. Pause/State Metadata**

State information is stored in:

```
models/saved_models/artifacts/cache/state_<hash>.json
```

Inspecting this file reveals:

* Last completed epoch
* Training status
* Latest logs

---

### **7. GPU Memory Management**

The script automatically sets:

```
TF_GPU_ALLOCATOR=cuda_malloc_async
```

This is done **before TensorFlow initializes**, so no extra environment configuration is needed.
You can still override it manually if desired.
