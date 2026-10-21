"""Storage migration for the original 8x8 cellular demo boards."""

import json
import sqlite3

from .schemas import CELLULAR_BOARD_SIZE, CELLULAR_CELL_COUNT, CellularWorld


def expand_cellular_boards(connection: sqlite3.Connection) -> None:
    """Expand all cellular history and slots together, preserving their metadata.

    Called in the database initialization transaction. Repeated initialization
    leaves already-expanded boards unchanged. This only changes stored layout;
    generation evaluation remains in Haskell.
    """
    for table, key in (('world_snapshots', 'sequence'), ('world_slots', 'slot')):
        rows = connection.execute(f'''
            SELECT state.conversation_id, state.{key}, state.world_json
            FROM {table} AS state JOIN conversations AS conversation
            ON conversation.id = state.conversation_id
            WHERE conversation.domain = 'cellular'
        ''').fetchall()
        for row in rows:
            world = json.loads(row['world_json'])
            if world.get('width') != 8 or world.get('height') != 8:
                continue
            if len(world['cells']) != 64:
                raise ValueError('Cannot expand an incomplete 8x8 cellular board')
            expanded = ['white'] * CELLULAR_CELL_COUNT
            offset = (CELLULAR_BOARD_SIZE - 8) // 2
            for y in range(8):
                for x in range(8):
                    expanded[x + offset + CELLULAR_BOARD_SIZE * (y + offset)] = world['cells'][x + 8 * y]
            world.update(width=CELLULAR_BOARD_SIZE, height=CELLULAR_BOARD_SIZE, cells=expanded)
            # Custom palettes need white to represent the new surrounding cells.
            if 'white' not in world['ruleset']['palette']:
                world['ruleset']['palette'].append('white')
            validated = CellularWorld.model_validate(world)
            connection.execute(f'''
                UPDATE {table} SET world_json = ? WHERE conversation_id = ? AND {key} = ?
            ''', (validated.model_dump_json(), row['conversation_id'], row[key]))
