import json
from pathlib import Path
import pytest
from openbrushlab.type1_vectors import vector_document,export_vectors
from openbrushlab.sessions import decode_frames

SHARED=Path(__file__).parents[1]/"ios/OpenBrush/OpenBrushTests/Fixtures/TYPE1Vectors.json"


def test_shared_corpus_is_exactly_regenerable():
    assert json.loads(SHARED.read_text(encoding="utf-8"))==vector_document()


@pytest.mark.parametrize("case",vector_document()["vectors"],ids=lambda c:c["id"])
def test_python_oracle_matches_each_shared_vector(case):
    assert decode_frames([bytes.fromhex(value) for value in case["notifications_hex"]],case["device_key"])==case["expected"]


def test_export_is_deterministic_and_requires_explicit_overwrite(tmp_path):
    a,b=tmp_path/"a.json",tmp_path/"b.json"
    export_vectors(a);export_vectors(b)
    assert a.read_bytes()==b.read_bytes()
    with pytest.raises(FileExistsError):export_vectors(a)
    export_vectors(a,overwrite=True)
    assert a.read_bytes()==b.read_bytes()


def test_exporter_never_loads_private_sources():
    import ast,inspect
    import openbrushlab.type1_vectors as module
    tree=ast.parse(inspect.getsource(module))
    assert not any(isinstance(node,ast.Attribute) and node.attr in {"read_text","read_bytes","glob","rglob"} for node in ast.walk(tree))
    doc=vector_document()
    assert doc["privacy"]=="synthetic-only-no-private-capture-input"
    assert len({c["id"] for c in doc["vectors"]})==len(doc["vectors"])
