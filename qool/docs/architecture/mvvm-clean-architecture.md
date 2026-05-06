# MVVM + Clean Architecture

## Directory Structure

```text
qool/
  Presentation/
    Views/
    ViewModels/
  Application/
    UseCases/
  Domain/
    Models/
    Repositories/
    Services/
  Infrastructure/
    Persistence/
```

## Dependency Direction

```text
View -> ViewModel -> UseCase -> Domain
Infrastructure -> Domain protocols
```

## Current Scope

- メモ一覧
- キャンバス
- 画像切り抜き
- 画像調整

The current implementation is a functional shell for the specification. The old image cutout algorithms can be moved into `Infrastructure` and called from `Application/UseCases` without coupling SwiftUI views to image-processing code.
