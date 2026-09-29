<div align="center">

# ⚡ flux

**Git, but simple.**

Save your work with one command, and get the latest with another.

![bash](https://img.shields.io/badge/bash-3.2%2B-4EAA25?logo=gnubash&logoColor=white)
![version](https://img.shields.io/badge/version-2.0.0-blue)
![platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey)

</div>

---

## 🚀 The two commands you need

```bash
flux -s        # save everything: pull → commit → push
flux sync      # get the latest changes
```

`flux -s` lists what changed and asks for a commit message. **Press Enter** to use one it writes for you, or pass the message inline:

```bash
flux -s "fix login bug"
```

## 📦 Install

```bash
git clone <this-repo> ~/code/flux
ln -s ~/code/flux/flux ~/bin/flux   # any folder on your PATH works
```

## 🧰 Everything else

| Command | Short | What it does |
|---|:-:|---|
| `flux status` | `st` | What's changed and what needs pushing |
| `flux diff` | `d` | See exactly what you changed |
| `flux log [n]` | `l` | Recent commits (default 10) |
| `flux undo` | `u` | Undo last commit, keep your changes |
| `flux branch [name]` | `b` | List branches, or switch to / create one |
| `flux open` | | Open the repo in your browser |
| `flux help` | `-h` | Show all commands |

> [!TIP]
> Add `-y` to any command to skip questions, e.g. `flux -s -y` commits with an auto-generated message.

## ✨ What it handles for you

- **Uncommitted changes when pulling**: they're set aside and restored automatically
- **New branches**: the first push publishes them to the remote
- **Nothing to commit**: it tells you, and still pushes any unpushed commits
- **Errors**: you see git's real message plus a hint on how to fix it

<details>
<summary><b>Resolving a merge conflict</b></summary>

<br>

If `flux -s` or `flux sync` stops on a conflict, fix the files it lists, then run:

```bash
git add -A && git rebase --continue
```

Or back out completely with `git rebase --abort`.

</details>

---

<div align="center">
<sub>Colors turn off automatically when output is piped, or when <code>NO_COLOR</code> is set.</sub>
</div>
