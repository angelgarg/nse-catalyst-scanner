import pipeline


def test_file_key():
    assert pipeline.file_key("M&M") == "M_M"
    assert pipeline.file_key("BAJAJ-AUTO") == "BAJAJ-AUTO"


def test_light_row_has_sparkline():
    s = {k: None for k in ("ticker", "name", "last_close", "last_date", "chg_1d", "ret_1m",
                           "ret_3m", "ann_vol", "beta", "cat_count", "last_cat_date",
                           "z_last", "vr_last", "pred_move", "pred_dir", "rsi", "mom5")}
    s.update(close=list(range(100)), sentiment={"label": "bullish"})
    row = pipeline.light_row(s)
    assert row["spark"] == list(range(70, 100)) and "sentiment" not in row
