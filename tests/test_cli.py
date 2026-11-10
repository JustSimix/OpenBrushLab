import pytest
from openbrushlab.cli import main, parser


@pytest.mark.parametrize("value", ["0", "-1", "nan", "inf"])
def test_reject_invalid_timeouts(value):
    with pytest.raises(SystemExit):
        parser().parse_args(["scan", "--total-timeout", value])


def test_offline_decoder_does_not_need_ble(capsys):
    assert main(["decode-status", "0303020e74500000"]) == 0
    assert '"battery": 80' in capsys.readouterr().out


def test_invalid_decoder_input(capsys):
    assert main(["decode-status", "secret-not-hex"]) == 1
    assert "secret-not-hex" not in capsys.readouterr().out


def test_target_is_required(monkeypatch):
    monkeypatch.delenv("OPENBRUSHLAB_ADDRESS", raising=False)
    with pytest.raises(SystemExit):
        main(["read"])


def test_no_transmit_calls_in_source():
    import ast
    from pathlib import Path
    root = Path(__file__).parents[1] / "src/openbrushlab"
    forbidden = {"write_gatt_char", "write_gatt_descriptor", "start_notify", "pair", "unpair"}
    for path in root.glob("*.py"):
        tree = ast.parse(path.read_text(encoding="utf-8"))
        for node in ast.walk(tree):
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
                assert node.func.attr not in forbidden
