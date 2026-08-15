# Phase 42.4: RC2 Polish - Background Panel Missing Icons & Names Fix

## Issue
When a background tab (inactive split pane) was rendering a list of files, the list items appeared completely blank (no icons, no names) and their sizes were displayed as "NaN G".

## Deep Root Cause Analysis
The issue was subtle and caused by how QML's `ListView` model injection interacts with JavaScript arrays versus native Qt `QVariantList` objects:

1. **State serialization**: When a user switches tabs, `TabOps.saveActiveTab()` captures the active tab's `NavState.entries` (which is a native `QVariantList` coming directly from the C++ `Backend.DirectoryModel` if default sorting is applied).
2. **Implicit JS Conversion**: Saving a `QVariantList` into a standard JavaScript array property (`TabsState.tabs[index].entries`) causes QML's JS engine to implicitly convert the Qt native list into a pure JavaScript Array.
3. **Model Context Shadowing**: When the user switches *back* and the tab becomes a background panel, `BackgroundPanel.qml` assigns this pure JavaScript Array to the `ListView`'s `_content` model. 
4. **The QML Delegate Behavior**: 
    - When a QML `ListView` receives a native `QVariantList` (acting as a QAbstractListModel), it exposes a `model` context property containing the roles (`model.name`, `model.size`, etc.).
    - When it receives a pure JavaScript array, it DOES NOT expose a `model` property. Instead, it exposes the JS object directly as `modelData`.
5. **The Bug**: `BackgroundPanel.qml` was explicitly attempting to pass `model` into the delegate:
   ```qml
   delegate: BackgroundListDelegate {
     modelData: model
     index: model.index
   }
   ```
   Because `model` is `undefined` for JS array models, `modelData` was explicitly assigned `undefined`, destroying the automatic injection provided by QML. Consequently, `BackgroundListDelegate.qml` tried to read `modelData.name`, resolving to empty strings or `NaN`.

## The Fix

1. **Removed the manual `modelData` assignments** from `BackgroundPanel.qml`.
2. **Adopted `required property var modelData`** and `required property int index` in `BackgroundListDelegate.qml` (identical to how `FileListRow.qml` operates).

By declaring `required property`, we instruct the QML engine to securely and automatically inject the correct context variables directly into the delegate, making it completely immune to whether the underlying list is a `QVariantList` or a pure JS Array.

*Selfchecks verified: 82/82 passing.*
