# ML training (offline)

Training runs on a local GPU or Colab, never on the server. Outputs are registered into `ml/service/models/` with `scripts/register_model.py` and fetched on servers with `scripts/fetch_models.sh`.

```bash
python -m venv .venv-train && . .venv-train/bin/activate
pip install -r ml/training/requirements-train.txt
```

## Vision (YOLOv8s, Section 8)
Dataset layout (gitignored, `ml/training/data/vision/<fish|produce>/`):
```
images/{train,val,test}/*.jpg
labels/{train,val,test}/*.txt     # YOLO format, class ids as in data_<category>.yaml
grades.csv                        # test split only: image,grade   (ground-truth A/B/C by an inspector)
```
Sources: Kaggle "Fruits fresh and rotten for classification", FruitNet (Indian fruits), Kaggle "A Large-Scale Fish Dataset", plus own photos (~1,500 target) labelled in Roboflow/CVAT, split 70/20/10. Record every source and licence in `vision/DATA_SOURCES.md` before training.

```bash
python ml/training/vision/train_yolo.py --category fish     # → runs/fish/…/weights/best.onnx + metrics.json
python scripts/register_model.py vision_fish v1 ml/training/vision/runs/fish/train/weights/best.onnx \
  --metrics ml/training/vision/runs/fish/metrics.json --classes fresh discoloured_skin damaged_torn sunken_eye --activate
```
Targets (ML-01): mAP@0.5 ≥ 0.80, grade accuracy ≥ 85 %. **Record the measured numbers, not the targets.**

## Shelf life (Cox PH)
Input CSV `ml/training/data/shelf_life/observations.csv`, one row per observed batch, every row traceable to `shelf_life/DATA_SOURCES.md`:
`source_id,product_code,base_shelf_life_h,mean_temp_c,degree_minutes_above,humidity_pct,ethylene_ppm,shock_events,grade,duration_h,event`
(`event` = 1 if spoilage was observed at `duration_h`, 0 if the observation ended without spoilage).

```bash
python ml/training/shelf_life/train_cox.py --data ml/training/data/shelf_life/observations.csv --out ml/training/shelf_life/out
python scripts/register_model.py shelf_life_cox v1 ml/training/shelf_life/out/cox_params.json \
  --metrics ml/training/shelf_life/out/metrics.json --activate
```
Targets (ML-02): C-index ≥ 0.75, error ≤ ±12 h. If there is not enough real data, **do not register a Cox model**: the service then uses the Q10 fallback, and TESTING.md records that.
