import pathlib

from pydantic import BaseModel

from tests.utils.alembic_reader import ALEMBIC_MIGRATIONS, import_file, latest_alembic_version


class AlembicMigration(BaseModel):
    path: pathlib.Path
    revision: str
    down_revisions: tuple[str, ...] = ()


def _read_migrations() -> list[AlembicMigration]:
    migrations: list[AlembicMigration] = []

    for path in sorted(ALEMBIC_MIGRATIONS.glob("*.py")):
        mod = import_file("alembic_version", path)

        down_revision = getattr(mod, "down_revision", None)
        if down_revision is None:
            down_revisions: tuple[str, ...] = ()
        elif isinstance(down_revision, str):
            down_revisions = (down_revision,)
        else:
            down_revisions = tuple(down_revision)

        migrations.append(AlembicMigration(path=path, revision=mod.revision, down_revisions=down_revisions))

    return migrations


def test_alembic_revisions_form_a_single_history() -> None:
    """
    feinarbyte build: upstream requires a strictly linear history here. This build merges
    feature branches that bring their own migrations, which are joined with upstream's
    by merge migrations (see .github/fork/README.md), so the history is a graph instead.

    It still has to
      - reference only revisions that exist
      - end in exactly one head, otherwise the app refuses to start
      - have that head in the last file by name, which `latest_alembic_version` relies on
    """
    migrations = _read_migrations()
    revisions = [migration.revision for migration in migrations]

    assert len(revisions) == len(set(revisions)), "duplicate revision ids"

    parents: set[str] = set()
    for migration in migrations:
        for down_revision in migration.down_revisions:
            assert down_revision in revisions, f"unknown down_revision {down_revision} in {migration.path}"
            parents.add(down_revision)

    heads = [revision for revision in revisions if revision not in parents]
    assert len(heads) == 1, f"expected exactly one alembic head, found {heads}"
    assert heads[0] == latest_alembic_version()
