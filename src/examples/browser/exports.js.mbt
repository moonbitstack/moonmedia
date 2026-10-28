// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Put `report` on the global object, where the page's own script can reach it.
///
/// The JavaScript build of a package is a script, not a module: it runs its
/// `main` and hands nothing back. One assignment is all the page needs.
extern "js" fn publish(report : (String) -> String) = "(fn) => { globalThis.moonmedia = { report: fn }; }"
