# Fixed Releases with a Private Bucket

[README.md](../README.md)  

---

`scoop update -a` installs whatever version the public buckets carry on that day. For a
single developer that is convenient; for a team it means that two machines updated a
week apart run different Gradle, Node or Python versions, and that a build which worked
on Monday can fail on Wednesday because a tool moved. A private bucket turns updates
into releases: a tool changes version when someone commits the new manifest, not when
upstream publishes it.

## What a bucket is

A bucket is a git repository with a `bucket\` directory of JSON manifests, one per app.
Scoop clones it under `C:\usr\buckets\<name>` and reads the manifests from there. The
public `main`, `extras`, `java` and `versions` buckets are nothing else. Hash
verification, extraction and shims work the same for every bucket.

## Setup

1. Create a repository, for example `entrisbanking/scoop-bucket`, with a `bucket\`
   directory. Copy the manifests of the tools the team uses from the public buckets at
   the versions you want (`C:\usr\buckets\main\bucket\gradle.json`, ...). Keep the
   `checkver` and `autoupdate` sections; they are what `checkver.ps1` uses later.
2. Add the bucket on each machine and install from it:

   ```powershell
   scoop bucket add entb https://github.com/entrisbanking/scoop-bucket
   scoop install entb/gradle
   ```

   An app installed from `entb/gradle` follows the `entb` manifest from then on. An app
   already installed from `main` keeps following `main` until it is reinstalled from
   `entb` (`scoop uninstall gradle; scoop install entb/gradle`, `persist` data survives).
3. To raise a version, run Scoop's own tooling in the bucket repository and commit the
   result; a pull request is the review:

   ```powershell
   C:\usr\apps\scoop\current\bin\checkver.ps1 -Dir .\bucket gradle -Update   # fetch newest version and hashes
   C:\usr\apps\scoop\current\bin\checkhashes.ps1 -Dir .\bucket gradle        # verify hashes against downloads
   ```

   The next `scoop update -a` on the team's machines moves to exactly that version.

## Where scoop-boot fits

Phase 2 of `scoop-complete-install.ps1` adds the buckets `extras`, `java` and `versions`
and installs its package list from them. Pointing the package list at a private bucket
(`entb/gradle` instead of `gradle`) and adding that bucket in Step 2 is a change in the
package list of the install script. Private buckets over HTTPS work on networks where
SSH is blocked; the bucket URL is cloned with Git's credential helper like any other
repository.

## What this does not solve

- Scoop itself still updates from `ScoopInstaller/Scoop` on `scoop update`. It can be
  pinned the same way, with a fork: `scoop config scoop_repo <url>` and
  `scoop config scoop_branch <branch>`.
- Tools that update themselves (JetBrains Toolbox, VS Code, browsers) are outside Scoop's
  control once started.
- A private bucket is about reproducibility, not about endpoint security. If a security
  update of a tool is blocked on a machine, that is a question for whoever manages the
  endpoint policy, not a reason to stay on the old version.

---

[README.md](../README.md)

---
