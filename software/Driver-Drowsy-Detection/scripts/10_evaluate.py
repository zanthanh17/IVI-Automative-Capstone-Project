#!/usr/bin/env python3
"""Script 10: Evaluate trained models."""

import os
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '2'

import tensorflow as tf
import numpy as np, matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import json, yaml
import seaborn as sns
from sklearn.metrics import (classification_report, confusion_matrix,
                              roc_curve, auc, precision_recall_curve)

with open("config.yaml") as f:
    cfg = yaml.safe_load(f)

for gpu in tf.config.list_physical_devices('GPU'):
    tf.config.experimental.set_memory_growth(gpu, True)


def evaluate_model(model_path, test_dir, task, input_size, out_dir="results"):
    os.makedirs(out_dir, exist_ok=True)
    model = tf.keras.models.load_model(model_path)

    test_ds = tf.keras.utils.image_dataset_from_directory(
        test_dir, image_size=(input_size, input_size),
        batch_size=32, label_mode="binary", shuffle=False
    )
    class_names = test_ds.class_names

    y_scores = model.predict(test_ds, verbose=1).flatten()
    y_pred   = (y_scores > 0.5).astype(int)
    y_true   = np.concatenate([y.numpy() for _, y in test_ds]).flatten().astype(int)

    report = classification_report(y_true, y_pred,
                                    target_names=class_names, digits=4, output_dict=True)
    print(f"\n{'='*50}")
    print(f"EVALUATION: {task.upper()}")
    print('='*50)
    print(classification_report(y_true, y_pred, target_names=class_names, digits=4))

    fpr, tpr, _ = roc_curve(y_true, y_scores)
    roc_auc_val = auc(fpr, tpr)
    print(f"ROC AUC: {roc_auc_val:.4f}")

    prec, rec, thrs = precision_recall_curve(y_true, y_scores)
    f1s = 2*prec*rec/(prec+rec+1e-8)
    best_thr = thrs[np.argmax(f1s[:-1])] if len(thrs) > 0 else 0.5
    print(f"Optimal threshold: {best_thr:.3f}")

    fig, axes = plt.subplots(1, 3, figsize=(18, 5))
    fig.suptitle(f"{task.upper()} Evaluation", fontsize=14, fontweight='bold')

    cm = confusion_matrix(y_true, y_pred, normalize='true')
    sns.heatmap(cm, annot=True, fmt='.2%', ax=axes[0],
                xticklabels=class_names, yticklabels=class_names, cmap='Blues')
    axes[0].set_title('Confusion Matrix')

    axes[1].plot(fpr, tpr, '#00d4ff', lw=2, label=f'AUC={roc_auc_val:.4f}')
    axes[1].plot([0, 1], [0, 1], 'k--'); axes[1].legend()
    axes[1].set_title('ROC Curve')

    axes[2].plot(rec[:-1], prec[:-1], '#ff6b35', lw=2)
    axes[2].set_title('Precision-Recall Curve')

    plt.tight_layout()
    plt.savefig(f"{out_dir}/{task}_evaluation.png", dpi=150)
    plt.close()

    result = {
        "task": task, "roc_auc": roc_auc_val,
        "accuracy": report["accuracy"],
        "optimal_threshold": float(best_thr),
        "report": report
    }
    with open(f"{out_dir}/{task}_results.json", "w") as f:
        json.dump(result, f, indent=2)

    targets = {"eye_val": 0.97, "eye_test": 0.97,
                "yawn_val": 0.95, "yawn_test": 0.95, "face": 0.95}
    target  = targets.get(task, 0.92)
    if roc_auc_val >= target:
        print(f"\n✅ {task} PASSED: AUC={roc_auc_val:.4f} ≥ {target}")
    else:
        print(f"\n❌ {task} FAILED: AUC={roc_auc_val:.4f} < {target}")
        print("   → Cần thêm data hoặc điều chỉnh hyperparameter")
    return result

if __name__ == "__main__":
    isize = cfg["data"]["img_size_region"]

    # Evaluate Eye CNN on val
    eye_model = "models/eye_cnn/final_fixed.keras"
    if os.path.exists(eye_model):
        print("\n" + "="*60)
        print("EYE CNN — Validation Set")
        print("="*60)
        evaluate_model(eye_model, "data/splits/eye/val", "eye_val", isize)

        # Evaluate Eye CNN on test
        eye_test = "data/splits/eye/test"
        if os.path.exists(eye_test):
            print("\n" + "="*60)
            print("EYE CNN — Test Set")
            print("="*60)
            evaluate_model(eye_model, eye_test, "eye_test", isize)

    # Evaluate Yawn CNN on val
    yawn_model = "models/yawn_cnn/final_fixed.keras"
    if os.path.exists(yawn_model):
        print("\n" + "="*60)
        print("YAWN CNN — Validation Set")
        print("="*60)
        evaluate_model(yawn_model, "data/splits/mouth/val", "yawn_val", isize)

        # Evaluate Yawn CNN on test
        yawn_test = "data/splits/mouth/test"
        if os.path.exists(yawn_test):
            print("\n" + "="*60)
            print("YAWN CNN — Test Set")
            print("="*60)
            evaluate_model(yawn_model, yawn_test, "yawn_test", isize)

    # Summary
    print("\n" + "="*60)
    print("EVALUATION SUMMARY")
    print("="*60)
    for rfile in sorted(os.listdir("results")):
        if rfile.endswith("_results.json"):
            with open(f"results/{rfile}") as f:
                r = json.load(f)
            print(f"  {r['task']:12s}  AUC={r['roc_auc']:.4f}  Acc={r['accuracy']:.4f}  Thr={r['optimal_threshold']:.3f}")
