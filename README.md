# Roblox Monorepo

Monorepo contenant les projets Roblox Studio (Rojo).

## Structure

```
projects/
  BrainrotHQ/   - Hub principal BrainrotHQ (radar, votes, monetisation)
  towerpower/   - Jeu Tower Power
tools/
  execExtract.bat         - Script d'extraction Windows
  extract_rlbx_script.py  - Extraction de scripts depuis .rbxlx
```

## Lancer un projet avec Rojo

```bash
# BrainrotHQ
rojo serve projects/BrainrotHQ/default.project.json

# TowerPower
rojo serve projects/towerpower/default.project.json
```

## Ajouter un nouveau projet

```bash
mkdir projects/MonJeu
# Creer projects/MonJeu/default.project.json et projects/MonJeu/src/
```
