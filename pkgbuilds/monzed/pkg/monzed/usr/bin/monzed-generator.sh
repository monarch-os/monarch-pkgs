#!/bin/bash

# monzed generator — Convert a Monarch colors.toml (or Alacritty TOML) to a Zed theme JSON.

set -euo pipefail

# Force C locale so printf "%.0f" understands awk's dot-decimal output regardless of LC_NUMERIC.
export LC_ALL=C

show_usage() {
    cat << 'EOF'
Usage: monzed-generator.sh <source_toml> [output_dir] [template_file] [appearance] [theme_name]

Arguments:
  source_toml    Path to colors.toml or alacritty.toml
  output_dir     Output directory (default: dirname of source_toml)
  template_file  Path to the .tpl template (default: alongside this script)
  appearance     "dark" or "light" (default: dark)
  theme_name     Display name written into the JSON (default: Monzed)
EOF
    exit 1
}

normalize_hex_color() {
    local color="$1"
    if [[ "$color" =~ ^0x ]]; then
        echo "#${color:2}"
    elif [[ "$color" =~ ^# ]]; then
        echo "$color"
    else
        echo "#$color"
    fi
}

hex_to_rgb() {
    local hex
    hex=$(normalize_hex_color "$1")
    hex="${hex#\#}"
    echo "$((16#${hex:0:2})) $((16#${hex:2:2})) $((16#${hex:4:2}))"
}

rgb_to_hex() {
    printf "#%02x%02x%02x" "$1" "$2" "$3"
}

lighten_color() {
    local hex="$1" factor="${2:-20}"
    read -r r g b <<< "$(hex_to_rgb "$hex")"
    r=$(( r + (255 - r) * factor / 100 ))
    g=$(( g + (255 - g) * factor / 100 ))
    b=$(( b + (255 - b) * factor / 100 ))
    r=$((r > 255 ? 255 : r))
    g=$((g > 255 ? 255 : g))
    b=$((b > 255 ? 255 : b))
    rgb_to_hex "$r" "$g" "$b"
}

darken_color() {
    local hex="$1" factor="${2:-20}"
    read -r r g b <<< "$(hex_to_rgb "$hex")"
    local multiplier=$((100 - factor))
    r=$((r * multiplier / 100))
    g=$((g * multiplier / 100))
    b=$((b * multiplier / 100))
    r=$((r < 0 ? 0 : r))
    g=$((g < 0 ? 0 : g))
    b=$((b < 0 ? 0 : b))
    rgb_to_hex "$r" "$g" "$b"
}

apply_alpha() {
    local hex="$1" percent="$2" alpha
    alpha=$((255 * percent / 100))
    printf "%s%02x" "$hex" "$alpha"
}

escape_sed() {
    local value="$1"
    value=${value//\\/\\\\}
    value=${value//&/\\&}
    value=${value//|/\\|}
    echo "$value"
}

rgb_to_hsl() {
    local hex="$1"
    read -r r g b <<< "$(hex_to_rgb "$hex")"

    local rf gf bf max min delta lightness saturation hue
    rf=$(awk "BEGIN {printf \"%.6f\", $r/255}")
    gf=$(awk "BEGIN {printf \"%.6f\", $g/255}")
    bf=$(awk "BEGIN {printf \"%.6f\", $b/255}")

    max=$(awk "BEGIN {m=$rf; if($gf>m) m=$gf; if($bf>m) m=$bf; print m}")
    min=$(awk "BEGIN {m=$rf; if($gf<m) m=$gf; if($bf<m) m=$bf; print m}")
    delta=$(awk "BEGIN {print $max - $min}")
    lightness=$(awk "BEGIN {print ($max + $min) / 2}")

    saturation=0
    if (( $(awk "BEGIN {print ($delta > 0.001)}") )); then
        saturation=$(awk "BEGIN {print $delta / (1 - sqrt(($lightness * 2 - 1) * ($lightness * 2 - 1)))}")
    fi

    hue=0
    if (( $(awk "BEGIN {print ($delta > 0.001)}") )); then
        if (( $(awk "BEGIN {print ($max == $rf)}") )); then
            hue=$(awk "BEGIN {h = 60 * ((($gf - $bf) / $delta) % 6); print h}")
        elif (( $(awk "BEGIN {print ($max == $gf)}") )); then
            hue=$(awk "BEGIN {print 60 * ((($bf - $rf) / $delta) + 2)}")
        else
            hue=$(awk "BEGIN {print 60 * ((($rf - $gf) / $delta) + 4)}")
        fi
    fi

    hue=$(awk "BEGIN {h=$hue; while(h<0) h+=360; while(h>=360) h-=360; print h}")
    echo "$hue $saturation $lightness"
}

rgb_to_hue() {
    read -r hue _ _ <<< "$(rgb_to_hsl "$1")"
    printf "%.0f" "$hue"
}

hsl_to_rgb() {
    local h="$1" s="$2" l="$3" c x m rf gf bf r g b

    c=$(awk "BEGIN {print $s * (1 - sqrt(($l * 2 - 1) * ($l * 2 - 1)))}")
    x=$(awk "BEGIN {print $c * (1 - sqrt((($h / 60) % 2 - 1) * (($h / 60) % 2 - 1)))}")
    m=$(awk "BEGIN {print $l - $c / 2}")

    rf=0; gf=0; bf=0
    if (( $(awk "BEGIN {print ($h >= 0 && $h < 60)}") )); then
        rf=$c; gf=$x; bf=0
    elif (( $(awk "BEGIN {print ($h >= 60 && $h < 120)}") )); then
        rf=$x; gf=$c; bf=0
    elif (( $(awk "BEGIN {print ($h >= 120 && $h < 180)}") )); then
        rf=0; gf=$c; bf=$x
    elif (( $(awk "BEGIN {print ($h >= 180 && $h < 240)}") )); then
        rf=0; gf=$x; bf=$c
    elif (( $(awk "BEGIN {print ($h >= 240 && $h < 300)}") )); then
        rf=$x; gf=0; bf=$c
    else
        rf=$c; gf=0; bf=$x
    fi

    r=$(awk "BEGIN {printf \"%.0f\", ($rf + $m) * 255}")
    g=$(awk "BEGIN {printf \"%.0f\", ($gf + $m) * 255}")
    b=$(awk "BEGIN {printf \"%.0f\", ($bf + $m) * 255}")
    r=$((r < 0 ? 0 : r > 255 ? 255 : r))
    g=$((g < 0 ? 0 : g > 255 ? 255 : g))
    b=$((b < 0 ? 0 : b > 255 ? 255 : b))
    rgb_to_hex "$r" "$g" "$b"
}

is_yellow() { local h; h=$(rgb_to_hue "$1"); (( $(awk "BEGIN {print ($h >= 40 && $h <= 70)}") )); }
is_green()  { local h; h=$(rgb_to_hue "$1"); (( $(awk "BEGIN {print ($h >= 80 && $h <= 160)}") )); }
is_red()    { local h; h=$(rgb_to_hue "$1"); (( $(awk "BEGIN {print ($h >= 340 || $h <= 20)}") )); }

synthesize_color() {
    local hex="$1" target_hue="$2" max_lightness="$3"
    read -r hue sat light <<< "$(rgb_to_hsl "$hex")"
    sat=$(awk "BEGIN {print ($sat > 0.4 ? $sat : 0.4)}")
    light=$(awk "BEGIN {print ($light > $max_lightness ? $light : $max_lightness)}")
    hsl_to_rgb "$target_hue" "$sat" "$light"
}

validate_color() {
    local normal="$1" bright="$2" check_fn="$3" synth_hue="$4" synth_max_l="$5" fallback="$6"

    if [[ -n "$normal" ]] && $check_fn "$normal"; then
        echo "$normal"
    elif [[ -n "$normal" ]]; then
        synthesize_color "$normal" "$synth_hue" "$synth_max_l"
    elif [[ -n "$bright" ]] && $check_fn "$bright"; then
        echo "$bright"
    else
        echo "$fallback"
    fi
}

parse_colors_toml() {
    local file_path="$1"

    while IFS='=' read -r key value; do
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        if [[ -z "$key" || "$key" == \#* ]]; then
            continue
        fi
        value=${value%\"}
        value=${value#\"}
        value=${value%\'}
        value=${value#\'}
        [[ -n "$value" ]] && value=$(normalize_hex_color "$value")

        case "$key" in
            accent) accent="$value" ;;
            cursor) cursor="$value" ;;
            foreground) foreground="$value" ;;
            background) background="$value" ;;
            selection_foreground) selection_foreground="$value" ;;
            selection_background) selection_background="$value" ;;
            color0) color0="$value" ;;
            color1) color1="$value" ;;
            color2) color2="$value" ;;
            color3) color3="$value" ;;
            color4) color4="$value" ;;
            color5) color5="$value" ;;
            color6) color6="$value" ;;
            color7) color7="$value" ;;
            color8) color8="$value" ;;
            color9) color9="$value" ;;
            color10) color10="$value" ;;
            color11) color11="$value" ;;
            color12) color12="$value" ;;
            color13) color13="$value" ;;
            color14) color14="$value" ;;
            color15) color15="$value" ;;
        esac
    done < "$file_path"
}

extract_alacritty_color() {
    local content="$1" section="$2" key="$3"
    echo "$content" | grep -A20 "\[colors\.${section}\]" | \
        grep -oP "${key}\\s*=\\s*[\"']*\\K(?:0x|#)?[0-9a-fA-F]+" | head -1 || echo ""
}

parse_alacritty_toml() {
    local file_path="$1" content
    content=$(cat "$file_path")

    background=$(echo "$content" | grep -oP 'background\s*=\s*["\'\'']*\K(?:0x|#)?[0-9a-fA-F]+' | head -1 || echo "")
    foreground=$(echo "$content" | grep -oP 'foreground\s*=\s*["\'\'']*\K(?:0x|#)?[0-9a-fA-F]+' | head -1 || echo "")

    [[ -n "$background" ]] && background=$(normalize_hex_color "$background")
    [[ -n "$foreground" ]] && foreground=$(normalize_hex_color "$foreground")

    local idx=0
    for color_name in black red green yellow blue magenta cyan white; do
        local normal bright
        normal=$(extract_alacritty_color "$content" "normal" "$color_name")
        bright=$(extract_alacritty_color "$content" "bright" "$color_name")
        [[ -n "$normal" ]] && eval "color$idx=\$(normalize_hex_color \"\$normal\")"
        [[ -n "$bright" ]] && eval "color$((idx + 8))=\$(normalize_hex_color \"\$bright\")"
        idx=$((idx + 1))
    done
}

finalize_palette_defaults() {
    if [[ -z "$background" || -z "$foreground" ]]; then
        echo "Error: background and foreground must be set in $input_file" >&2
        exit 1
    fi

    if [[ -z "$accent" ]]; then
        accent="${color4:-$foreground}"
    fi

    cursor="${cursor:-$foreground}"
    selection_foreground="${selection_foreground:-$background}"
    selection_background="${selection_background:-$foreground}"

    color0="${color0:-#000000}"
    color1="${color1:-#ff4444}"
    color2="${color2:-#44ff44}"
    color3="${color3:-#ffff44}"
    color4="${color4:-$accent}"
    color5="${color5:-#ff44ff}"
    color6="${color6:-#44ffff}"
    color7="${color7:-$foreground}"
    color8="${color8:-$color0}"
    color9="${color9:-$color1}"
    color10="${color10:-$color2}"
    color11="${color11:-$color3}"
    color12="${color12:-$color4}"
    color13="${color13:-$color5}"
    color14="${color14:-$color6}"
    color15="${color15:-$color7}"
}

compute_derived_colors() {
    if [[ "$appearance" == "light" ]]; then
        background_darker=$(darken_color "$background" 12)
        background_lighter=$(darken_color "$background" 4)
        background_much_lighter=$(darken_color "$background" 18)
        foreground_muted=$(darken_color "$foreground" 40)
    else
        background_darker=$(darken_color "$background" 25)
        background_lighter=$(lighten_color "$background" 10)
        background_much_lighter=$(lighten_color "$background" 20)
        foreground_muted=$(darken_color "$foreground" 40)
    fi

    accent_20=$(apply_alpha "$accent" 20)
    accent_40=$(apply_alpha "$accent" 40)

    color1_20=$(apply_alpha "$color1" 20)
    color2_20=$(apply_alpha "$color2" 20)
    color3_20=$(apply_alpha "$color3" 20)
    color3_40=$(apply_alpha "$color3" 40)
    color4_20=$(apply_alpha "$color4" 20)
    color5_20=$(apply_alpha "$color5" 20)
    color6_20=$(apply_alpha "$color6" 20)

    ensured_red=$(validate_color   "$color1" "$color9"  is_red    0   0.40 "#ff4444")
    ensured_green=$(validate_color "$color2" "$color10" is_green  120 0.37 "#44ff44")
    ensured_yellow=$(validate_color "$color3" "$color11" is_yellow 55  0.40 "#ffff00")

    if [[ "$appearance" == "light" ]]; then
        ensured_red=$(darken_color "$ensured_red" 18)
        ensured_green=$(darken_color "$ensured_green" 18)
        ensured_yellow=$(darken_color "$ensured_yellow" 25)
    fi

    ensured_red_20=$(apply_alpha "$ensured_red" 20)
    ensured_green_20=$(apply_alpha "$ensured_green" 20)
    ensured_yellow_20=$(apply_alpha "$ensured_yellow" 20)
    ensured_yellow_40=$(apply_alpha "$ensured_yellow" 40)
}

render_template() {
    local template_file="$1" output_file="$2"
    local content
    content=$(cat "$template_file")

    local replacements=(
        "theme_name" "$theme_name"
        "appearance" "$appearance"
        "accent" "$accent"
        "cursor" "$cursor"
        "foreground" "$foreground"
        "background" "$background"
        "selection_foreground" "$selection_foreground"
        "selection_background" "$selection_background"
        "color0" "$color0" "color1" "$color1" "color2" "$color2" "color3" "$color3"
        "color4" "$color4" "color5" "$color5" "color6" "$color6" "color7" "$color7"
        "color8" "$color8" "color9" "$color9" "color10" "$color10" "color11" "$color11"
        "color12" "$color12" "color13" "$color13" "color14" "$color14" "color15" "$color15"
        "background_darker" "$background_darker"
        "background_lighter" "$background_lighter"
        "background_much_lighter" "$background_much_lighter"
        "foreground_muted" "$foreground_muted"
        "accent_20" "$accent_20" "accent_40" "$accent_40"
        "color1_20" "$color1_20" "color2_20" "$color2_20"
        "color3_20" "$color3_20" "color3_40" "$color3_40"
        "color4_20" "$color4_20" "color5_20" "$color5_20" "color6_20" "$color6_20"
        "ensured_red" "$ensured_red" "ensured_green" "$ensured_green" "ensured_yellow" "$ensured_yellow"
        "ensured_red_20" "$ensured_red_20" "ensured_green_20" "$ensured_green_20"
        "ensured_yellow_20" "$ensured_yellow_20" "ensured_yellow_40" "$ensured_yellow_40"
    )

    local index=0
    while [[ $index -lt ${#replacements[@]} ]]; do
        local key=${replacements[$index]}
        local value=${replacements[$((index + 1))]}
        value=$(escape_sed "$value")
        content=$(printf "%s" "$content" | sed "s|{{${key}}}|${value}|g")
        index=$((index + 2))
    done

    printf "%s" "$content" > "$output_file"
}

main() {
    if [[ $# -eq 1 && ("$1" == "-h" || "$1" == "--help") ]]; then
        show_usage
    fi

    if [[ $# -lt 1 || $# -gt 5 ]]; then
        show_usage
    fi

    local input_file="$1"
    local output_dir="${2:-}"
    local template_file="${3:-}"
    appearance="${4:-dark}"
    theme_name="${5:-Monzed}"

    accent=""; cursor=""; foreground=""; background=""
    selection_foreground=""; selection_background=""
    for i in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
        eval "color$i=\"\""
    done

    local script_dir
    script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    if [[ -z "$template_file" ]]; then
        template_file="$script_dir/monzed-theme.tpl"
    fi

    if [[ ! -f "$input_file" ]]; then
        echo "Error: File $input_file not found" >&2
        exit 1
    fi

    if [[ ! -f "$template_file" ]]; then
        echo "Error: Template file not found: $template_file" >&2
        exit 1
    fi

    if [[ -z "$output_dir" ]]; then
        output_dir="$(dirname "$input_file")"
    fi

    if [[ "$appearance" != "dark" && "$appearance" != "light" ]]; then
        echo "Error: appearance must be 'dark' or 'light'" >&2
        exit 1
    fi

    if [[ "$input_file" == *.toml ]]; then
        if grep -q "^accent\s*=\|^color0\s*=" "$input_file" 2>/dev/null; then
            parse_colors_toml "$input_file"
        else
            parse_alacritty_toml "$input_file"
        fi
    else
        parse_alacritty_toml "$input_file"
    fi

    finalize_palette_defaults
    compute_derived_colors

    mkdir -p "$output_dir"
    local theme_slug
    theme_slug=$(echo "$theme_name" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | sed 's/-\+/-/g; s/^-\|-$//g')
    [[ -z "$theme_slug" ]] && theme_slug="monzed"
    local output_file="$output_dir/${theme_slug}.json"

    render_template "$template_file" "$output_file"

    echo "Generated theme: $output_file"
    echo "Theme name: $theme_name"
    echo "Appearance: $appearance"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
