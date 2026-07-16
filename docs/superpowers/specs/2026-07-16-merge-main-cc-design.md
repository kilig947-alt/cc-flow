# Merge Main into CC FLOW Migration

## Goal

Preserve the current uncommitted CC FLOW migration, incorporate the latest
changes from `origin/main`, update the public README to describe the resulting
project accurately, and publish the completed result to `fork/main`.

The previously discussed `.trae` to `.cc` domain-model migration is explicitly
out of scope.

## Starting State

- The current branch is `codex/cc-flow-migration` at the older local
  `origin/main` commit `b0600aa`.
- The working tree contains the large CC FLOW migration, including the
  `TraeFlow` to `CCFlow` project rename and additional feature work.
- Both remote `main` branches currently resolve to `c08cf77` when queried
  directly.
- `merge_main_cc` does not currently exist locally or on either remote.

## Integration Strategy

1. Create `merge_main_cc` from the current checkout so every existing working
   tree change remains in place.
2. Review the migration diff for accidental generated files, secrets, build
   output, or unrelated temporary artifacts.
3. Commit the current CC FLOW migration in coherent conventional commits. The
   current working tree must be clean before merging upstream.
4. Fetch `origin/main` and merge it into `merge_main_cc` with a merge commit.
   Do not rebase or force-push the migration.
5. Resolve conflicts by preserving the CC FLOW product identity and paths while
   incorporating upstream behavior and fixes. For conflicts in renamed files,
   compare the old `TraeFlow` source, the current `CCFlow` source, and the
   incoming upstream version rather than choosing one side wholesale.
6. Update `README.md` after the merge so it describes the final code rather
   than either pre-merge side.
7. Run proportional build and test verification, address failures introduced
   by the integration, and distinguish any remaining pre-existing failures.
8. Push `merge_main_cc` to `fork/main` without force:

   ```bash
   git push fork merge_main_cc:main
   ```

Because the merge commit will contain `c08cf77` as an ancestor, the update to
`fork/main` should be a normal fast-forward.

## README Scope

The README update will be evidence-based and aligned with the merged tree. It
will cover:

- CC FLOW product name, supported integrations, and current feature set.
- Correct Xcode project, scheme, build, test, and packaging commands.
- Current runtime paths such as `~/.cc-flow` and `/tmp/cc-flow.sock`.
- Correct repository clone, release, issue, and image links for
  `kilig947-alt/cc-flow` where the project is now published.
- Accurate signing and local installation guidance.
- Removal or correction of stale TRAE FLOW project-name references while
  retaining references to real TRAE clients where the application still
  supports them.

## Conflict Policy

- Preserve user-authored working-tree changes unless an incoming upstream fix
  must be adapted to the renamed CC FLOW location.
- Preserve real TRAE client identifiers, bundle identifiers, URL schemes, and
  hook paths; they are integrations, not stale project branding.
- Keep CC FLOW runtime identifiers and paths as the canonical app identity.
- Do not introduce compatibility work or model renames outside the merge and
  documentation scope.
- Do not discard files with reset, checkout, or other destructive commands.

## Verification

Run, at minimum:

```bash
xcodebuild -project CCFlow.xcodeproj -scheme CCFlow \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO build

swift test --package-path Prototype

xcodebuild -project CCFlow.xcodeproj -scheme CCFlow \
  -configuration Debug CODE_SIGNING_ALLOWED=NO \
  test -only-testing:CCFlowTests
```

Also run `git diff --check`, validate localization property lists, and inspect
the final branch history and remote ancestry before pushing.

## Completion Criteria

- `merge_main_cc` contains the committed CC FLOW migration and latest
  `origin/main` changes.
- The working tree is clean.
- README content matches the merged project and its publication location.
- Builds and tests pass, or any unavoidable pre-existing failure is explicitly
  documented and does not originate from the merge.
- `fork/main` points to the verified `merge_main_cc` tip through a non-force
  push.
