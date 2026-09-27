"""Validate the generated runtime contract against the OpenAPI 3.1 metaschema."""
import json
from pathlib import Path
from openapi_spec_validator import validate

validate(json.loads((Path(__file__).resolve().parents[1] / "contracts/openapi.json").read_text()))
print("PASS: OpenAPI 3.1 metaschema validation.")
