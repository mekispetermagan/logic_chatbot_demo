"""Storage encoding migrations; semantic validation remains in Haskell."""
import json


LEGACY_ATTRIBUTES = {
    **dict.fromkeys(("red", "blue", "green", "yellow"), "color"),
    **dict.fromkeys(("small", "medium", "large"), "size"),
    **dict.fromkeys(("bloom", "spark", "drop", "loop"), "shape"),
}


def migrate_attribute_encoding(connection) -> None:
    # World and salience history move together, once, in a single transaction.
    connection.execute("BEGIN IMMEDIATE")
    if connection.execute("PRAGMA user_version").fetchone()[0] >= 1:
        return
    rows = connection.execute(
        "SELECT conversation_id, sequence, world_json, salience_json FROM world_snapshots"
    ).fetchall()
    for row in rows:
        world = json.loads(row["world_json"])
        salience = json.loads(row["salience_json"])
        for item in world["objects"]:
            attributes = item.setdefault("attributes", {})
            for name in ("color", "size", "shape"):
                value = item.pop(name, None)
                if value is not None:
                    if name in attributes and attributes[name] != value:
                        raise ValueError("Conflicting legacy attributes")
                    attributes[name] = value
        for mention in salience:
            for prop in mention["properties"]:
                if prop["kind"] == "descriptor":
                    prop["kind"] = "attribute"
                    prop["attribute"] = LEGACY_ATTRIBUTES[prop["value"]]
        connection.execute(
            "UPDATE world_snapshots SET world_json = ?, salience_json = ? "
            "WHERE conversation_id = ? AND sequence = ?",
            (json.dumps(world), json.dumps(salience), row["conversation_id"], row["sequence"]),
        )
    connection.execute("PRAGMA user_version = 1")
