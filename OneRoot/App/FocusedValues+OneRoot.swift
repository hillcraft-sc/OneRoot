//
//  FocusedValues+OneRoot.swift
//
//  Intentionally empty.
//
//  The main-menu commands used to reach the frontmost window through five
//  separate `@FocusedValue` keys defined here. That churned the whole
//  `.commands` tree on every window render (see `WindowMenuState`). They were
//  replaced by a single `@FocusedObject` on `WindowMenuState`, published by
//  `MainWindowView` via `.focusedSceneObject(_:)`, which needs no
//  `FocusedValueKey`. This file is kept (rather than removed from the Xcode
//  project) only to avoid a project-file edit; it can be deleted whenever the
//  project file is next touched.
//
