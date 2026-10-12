# feinarbyte build of Mealie

This fork publishes its own Mealie image: upstream `mealie-next` plus feature
branches that are not (yet) merged upstream.

| Branch                 | Purpose                                                                 |
| ---------------------- | ----------------------------------------------------------------------- |
| `mealie-next`          | Untouched mirror of upstream. Base for feature branches and upstream PRs. |
| `feat/*`, `fix/*`      | One branch per feature, branched from `mealie-next`.                     |
| `feinarbyte/main`      | Integration branch and default branch. Upstream + all features. Always points at the last published build. |
| `feinarbyte/candidate` | Scratch branch of the workflow, force-pushed on every run. Never work on it. |

Image: `ghcr.io/feinarbyte/mealie`, tags `latest`, `<yyyymmdd>-<sha>` and `sha-<sha>`.

## How it works

`.github/workflows/fork-build.yml` runs every night, on every push to
`feinarbyte/main`, and on demand (`gh workflow run fork-build.yml`). It

1. fast-forwards the `mealie-next` mirror,
2. runs `.github/fork/sync.sh`: merges upstream `mealie-next` and every branch
   in `branches.txt` into `feinarbyte/main`, then joins the Alembic history,
3. runs the backend and frontend tests on the result,
4. builds and pushes the image,
5. fast-forwards `feinarbyte/main` to the tested commit.

If a step fails, nothing is published and `feinarbyte/main` does not move. The
running instance simply stays on the last good image.

The workflow pushes with the deploy key in the `FORK_SYNC_SSH_KEY` secret,
because `GITHUB_TOKEN` may not push changes to workflow files, which upstream
merges contain regularly.

## Everyday tasks

**Add a feature.** Branch from `mealie-next`, push to this repository, add the
branch name to `branches.txt` on `feinarbyte/main`, push. Later commits on the
feature branch are picked up automatically by the next run.

**Resolve a merge conflict.** The workflow fails and names the files.

```bash
git switch feinarbyte/main && git pull
.github/fork/sync.sh     # stops at the conflict
# resolve, then: git add ... && git commit
.github/fork/sync.sh     # repeat until it finishes
git push
```

If the conflict is between a feature and upstream, the cleaner fix is usually
to merge `mealie-next` into the feature branch, since the upstream PR needs
that anyway. The next run then merges without a conflict.

**Drop a feature.** Remove it from `branches.txt` and revert its merge commits
on `feinarbyte/main` (`git revert -m 1 <merge>`). If the feature had a
migration, restore the migration file afterwards and keep it: deployed
databases have applied it, and the migration check insists on it. The columns
it created simply stay in the database unused.

**A feature was merged upstream.** Remove it from `branches.txt`. Nothing else
is needed unless the migration check below complains.

## Database migrations

Upstream keeps a strictly linear Alembic history. Feature branches add
migrations of their own, so after upstream adds a migration the history has
two heads and Mealie will not start. `migrations.py` handles this:

- **Two heads are joined by an empty merge migration**, generated and committed
  automatically (`..._feinarbyte_merge_heads.py`).
- **Published history is append-only.** `migrations.lock` lists every migration
  that was part of a published build together with its parents. The run fails
  if one of them disappears or gets different parents.

The second rule is the important one. A database records only the head it is
at. If a migration it has already applied is later moved on top of a newer
upstream migration, Alembic considers that upstream migration applied and
skips it, and the schema is silently wrong. This is exactly what happens when a
feature branch is rebased for its upstream PR, so expect to see the check fail
now and then:

- *"parents changed"*: the feature branch re-parented its migration. On
  `feinarbyte/main`, restore the migration file as it was
  (`git checkout origin/feinarbyte/main -- mealie/alembic/versions/<file>`,
  delete the renamed copy) and commit. The merge migration takes care of the rest.
- *"defined twice"*: upstream merged the feature and re-dated the migration
  file. Delete the incoming copy, keep the one named in `migrations.lock`.
  Only do this if both files make the same schema change.

`tests/unit_tests/test_alembic.py` is changed in this fork accordingly: it
checks for a single head instead of a linear history.

Never edit `migrations.lock` to make the check pass unless you are certain that
no deployed database has applied the migrations in question.

## Deploying

Use `ghcr.io/feinarbyte/mealie:latest`, or pin a dated tag to roll back.
This is nightly upstream code and Mealie migrations cannot be downgraded:
**back up the database before pulling a new image.**
