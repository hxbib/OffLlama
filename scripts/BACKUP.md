# GitHub backup procedure (box -> Habib's PC -> GitHub)

Remote: https://github.com/hxbib/pocket-glimmer (PRIVATE until submission day).
The box has no GitHub login. Habib's Windows PC (agent machineId `42c228be-afea-4819-8d9e-b1ef473ecd2a`)
has `gh` logged in as `hxbib`. Never print, copy or export the token. Never force-push.
Stay out of `C:\pocket-glimmer-backup` and the PC GPU (used by another task).

## Repeat (any agent)
1. **Box Shell**: `cd /workspace/pocket-glimmer && scripts/backup_push.sh`
   (`BACKUP_AUTOCOMMIT=1 scripts/backup_push.sh` to also commit pending work first;
   .gitignore keeps weights/checkpoints/venvs/media out). If it prints `NOTHING_NEW`, stop.
2. **CopyFromBox** (agent tool): box `/workspace/pg.bundle` to the PC with NO computer_path
   (writes outside the PC's local-exec root such as `C:\src` are refused; it lands at `C:\Users\habib\pg.bundle`).
3. **PC Shell** (machineId above, PowerShell):
   ```powershell
   Move-Item -Force C:\Users\habib\pg.bundle C:\src\pg.bundle
   cd C:\src\pocket-glimmer
   git bundle verify C:\src\pg.bundle
   git fetch C:\src\pg.bundle "+refs/heads/*:refs/remotes/bundle/*"
   git for-each-ref --format="%(refname:lstrip=3)" refs/remotes/bundle | % { git push origin "refs/remotes/bundle/$($_):refs/heads/$_" }
   git push origin --tags
   git ls-remote origin
   ```
   A rejected (non-fast-forward) push means history diverged: stop and report; do not force.
4. **Box Shell**: `git update-ref refs/backup/pushed HEAD` (marks the base for the next incremental bundle).
5. **Verify**: box `git rev-parse HEAD; git rev-list --count HEAD` must equal
   PC `gh api repos/hxbib/pocket-glimmer/commits/master --jq .sha` and the ls-remote master hash.

If the incremental bundle fails to verify on the PC (missing prerequisite), delete
`refs/backup/pushed` on the box (`git update-ref -d refs/backup/pushed`) and rerun for a full bundle.
