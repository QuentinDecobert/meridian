# Fonts bundle — Meridian

Ce dossier doit contenir les fichiers **Geist** et **Geist Mono** qui alimentent `TypeScale`. Les deux familles sont **libres (SIL Open Font License)** et téléchargeables sur Google Fonts ou directement chez Vercel.

## À télécharger

### Geist (display / UI)

- Source : [Google Fonts · Geist](https://fonts.google.com/specimen/Geist) ou [github.com/vercel/geist-font](https://github.com/vercel/geist-font)
- Poids à embarquer : **Regular 400**, **Medium 500**, **SemiBold 600**, **Bold 700**
- Fichiers attendus (OTF ou TTF) :
  - `Geist-Regular.otf` (ou `.ttf`)
  - `Geist-Medium.otf`
  - `Geist-SemiBold.otf`
  - `Geist-Bold.otf`

### Geist Mono (data / numerics)

- Source : [Google Fonts · Geist Mono](https://fonts.google.com/specimen/Geist+Mono) ou même dépôt Vercel
- Poids : **Regular 400**, **Medium 500**, **SemiBold 600**
- Fichiers attendus :
  - `GeistMono-Regular.otf`
  - `GeistMono-Medium.otf`
  - `GeistMono-SemiBold.otf`

## Installation

1. Télécharger les archives depuis une des sources ci-dessus
2. Déposer les fichiers `.otf` (ou `.ttf`) **directement dans ce dossier** (pas de sous-dossier)
3. Relancer `xcodegen generate` à la racine du projet pour que Xcode les intègre comme ressources
4. **⌘R** dans Xcode — les fonts seront chargées automatiquement via `ATSApplicationFontsPath` défini dans `Info.plist`

## Fallback si les fonts ne sont pas installées

`Font.custom("Geist", size: …)` tombe silencieusement sur le font système si le family name n'est pas enregistré. L'app continue de fonctionner, juste sans la signature Geist. Idéal pour ne pas bloquer le build si les fonts manquent.

## Vérification

Pour confirmer qu'une font est bien chargée au runtime, ajouter temporairement dans `MeridianApp.init()` :

```swift
NSFontManager.shared.availableFontFamilies.filter { $0.contains("Geist") }
    .forEach { print("Loaded:", $0) }
```

On doit voir `Geist` et `Geist Mono` listés.
