from pathlib import Path

import tensorflow as tf

SEED = 42
IMG_SIZE = (224, 224)
BATCH_SIZE = 32
VAL_SPLIT = 0.2
BASE_EPOCHS = 25
FINE_TUNE_EPOCHS = 10
DATASET_DIR = Path("dataset_clean")
OUT_DIR = Path("model_artifacts")


def build_datasets():
    train_ds = tf.keras.utils.image_dataset_from_directory(
        DATASET_DIR,
        validation_split=VAL_SPLIT,
        subset="training",
        seed=SEED,
        image_size=IMG_SIZE,
        batch_size=BATCH_SIZE,
    )

    val_ds = tf.keras.utils.image_dataset_from_directory(
        DATASET_DIR,
        validation_split=VAL_SPLIT,
        subset="validation",
        seed=SEED,
        image_size=IMG_SIZE,
        batch_size=BATCH_SIZE,
    )

    class_names = train_ds.class_names
    auto = tf.data.AUTOTUNE
    train_ds = train_ds.shuffle(1000).prefetch(auto)
    val_ds = val_ds.prefetch(auto)

    return train_ds, val_ds, class_names


def compute_class_weight(class_names):
    counts = {}
    for name in class_names:
        counts[name] = len(list((DATASET_DIR / name).glob("*")))

    max_count = max(counts.values())
    weights = {i: max_count / counts[name] for i, name in enumerate(class_names)}
    return counts, weights


def build_model(num_classes):
    augment = tf.keras.Sequential(
        [
            tf.keras.layers.RandomFlip("horizontal"),
            tf.keras.layers.RandomRotation(0.08),
            tf.keras.layers.RandomZoom(0.08),
            tf.keras.layers.RandomContrast(0.10),
        ],
        name="data_aug",
    )

    base = tf.keras.applications.MobileNetV2(
        input_shape=IMG_SIZE + (3,),
        include_top=False,
        weights="imagenet",
    )
    base.trainable = False

    inputs = tf.keras.Input(shape=IMG_SIZE + (3,))
    x = augment(inputs)
    x = tf.keras.applications.mobilenet_v2.preprocess_input(x)
    x = base(x, training=False)
    x = tf.keras.layers.GlobalAveragePooling2D()(x)
    x = tf.keras.layers.Dropout(0.25)(x)
    outputs = tf.keras.layers.Dense(num_classes, activation="softmax")(x)

    model = tf.keras.Model(inputs, outputs)
    return model, base


def export_tflite(model, class_names):
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    model.save(OUT_DIR / "model.keras")

    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    float_model = converter.convert()
    (OUT_DIR / "model.tflite").write_bytes(float_model)

    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    quant_model = converter.convert()
    (OUT_DIR / "model_quant.tflite").write_bytes(quant_model)

    with open(OUT_DIR / "labels.txt", "w", encoding="utf-8") as handle:
        for idx, name in enumerate(class_names):
            handle.write(f"{idx} {name}\n")


def main():
    tf.keras.utils.set_random_seed(SEED)

    train_ds, val_ds, class_names = build_datasets()
    counts, class_weight = compute_class_weight(class_names)

    print("Class order:", class_names)
    print("Class counts:", counts)
    print("Class weights:", class_weight)

    model, base = build_model(num_classes=len(class_names))
    model.compile(
        optimizer=tf.keras.optimizers.Adam(1e-3),
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )

    callbacks = [
        tf.keras.callbacks.EarlyStopping(
            monitor="val_loss",
            patience=5,
            restore_best_weights=True,
        ),
        tf.keras.callbacks.ReduceLROnPlateau(
            monitor="val_loss",
            factor=0.5,
            patience=2,
        ),
    ]

    model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=BASE_EPOCHS,
        class_weight=class_weight,
        callbacks=callbacks,
    )

    base.trainable = True
    for layer in base.layers[:-30]:
        layer.trainable = False

    model.compile(
        optimizer=tf.keras.optimizers.Adam(1e-5),
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )
    model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=FINE_TUNE_EPOCHS,
        class_weight=class_weight,
        callbacks=callbacks,
    )

    val_loss, val_acc = model.evaluate(val_ds)
    print("Final validation loss:", val_loss)
    print("Final validation accuracy:", val_acc)

    export_tflite(model, class_names)
    print("Artifacts written to:", OUT_DIR)


if __name__ == "__main__":
    main()
