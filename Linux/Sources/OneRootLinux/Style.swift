/// OneRoot's few additions to the libadwaita look.
enum Style {
    static let css = """
    .oneroot-pathbar {
        background-color: alpha(currentColor, 0.08);
        border-radius: 8px;
        min-height: 34px;
        padding: 0 2px;
    }
    .oneroot-pathbar entry { background: none; box-shadow: none; }
    .oneroot-crumbs button { padding: 2px 6px; min-height: 26px; font-weight: normal; }
    .oneroot-crumb-current { font-weight: bold; }
    .oneroot-status { padding: 4px 12px; }
    .oneroot-operations-header { padding: 6px 12px 0 12px; }
    .oneroot-operation-row { padding: 6px 12px; }
    .oneroot-operations-options { padding: 4px 12px 8px 12px; }
    .oneroot-file-list row { min-height: 28px; }
    .oneroot-drop-target { background-color: alpha(@accent_bg_color, 0.3); border-radius: 6px; }
    .oneroot-drop-background { box-shadow: inset 0 0 0 2px @accent_bg_color; }
    .oneroot-filter-bar { padding: 6px 8px 2px 8px; }
    .oneroot-chip {
        background-color: alpha(@accent_bg_color, 0.12);
        border: 1px solid alpha(@accent_bg_color, 0.35);
        border-radius: 999px;
        padding: 0 2px 0 4px;
    }
    .oneroot-chip button { min-height: 22px; min-width: 0; padding: 0 6px; }
    .oneroot-chip-error { background-color: alpha(@error_bg_color, 0.12); border-color: alpha(@error_bg_color, 0.6); }
    .oneroot-stacked-segment { min-width: 0; min-height: 0; padding: 0; border-radius: 4px; box-shadow: none; border: none; }
    .oneroot-visualize-selected { background-color: alpha(currentColor, 0.1); }
    .oneroot-stacked-dim { opacity: 0.7; }
    .oneroot-chart-swatch { min-width: 10px; min-height: 10px; border-radius: 5px; }
    .oneroot-treemap-block { padding: 4px 6px; border-radius: 4px; min-width: 0; min-height: 0; box-shadow: none; border: none; }
    .oneroot-treemap-folder { background-color: @accent_bg_color; color: @accent_fg_color; }
    .oneroot-treemap-file { background-color: alpha(currentColor, 0.2); }
    .oneroot-treemap-other { background-color: alpha(currentColor, 0.1); }
    button.oneroot-treemap-block.oneroot-treemap-folder label.oneroot-treemap-text { color: @accent_fg_color; opacity: 1; }
    .oneroot-treemap-folder:hover { background-color: shade(@accent_bg_color, 1.12); }
    .oneroot-treemap-file:hover { background-color: alpha(currentColor, 0.3); }
    .oneroot-compare-bar { padding: 4px 10px; min-height: 30px; background-color: alpha(@accent_bg_color, 0.08); }
    .oneroot-cmp-only { color: @accent_color; font-weight: 600; }
    .oneroot-cmp-newer { color: @success_color; font-weight: 600; }
    .oneroot-cmp-differs { color: @warning_color; font-weight: 600; }
    .oneroot-grid-group { border-bottom: 2px solid alpha(@accent_bg_color, 0.55); padding: 4px 6px 2px 6px; margin: 10px 4px 0 4px; }
    .oneroot-grid-group label { color: @accent_color; font-weight: 700; }
    .oneroot-focused-pane { box-shadow: inset 0 2px 0 0 @accent_bg_color; }
    """
}
