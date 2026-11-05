import QtQuick

// Font Awesome glyph by name, e.g. Icon { name: "play" }. The names are the
// cases of glyph() below (a function, so every Icon shares one table).
Text {
    property string name
    property real size: 16

    // Font Awesome 6 Free Solid codepoints ("" for an unknown name)
    function glyph(iconName) {
        switch (iconName) {
        case "play": return "\uf04b"
        case "pause": return "\uf04c"
        case "next": return "\uf051"
        case "prev": return "\uf048"
        case "shuffle": return "\uf074"
        case "repeat": return "\uf01e"
        case "volume": return "\uf028"
        case "volumeLow": return "\uf027"
        case "volumeMute": return "\uf6a9"
        case "list": return "\uf03a"
        case "grid": return "\uf00a"
        case "thumbtack": return "\uf08d"
        case "music": return "\uf001"
        case "folderOpen": return "\uf07c"
        case "close": return "\uf00d"
        case "info": return "\uf05a"
        case "sortUp": return "\uf0d8"
        case "sortDown": return "\uf0d7"
        case "sortList": return "\uf160"
        case "layout": return "\uf0db"
        case "wave": return "\uf83e"
        case "sparkles": return "\uf72b"
        case "chevronDown": return "\uf078"
        case "chevronRight": return "\uf054"
        case "trash": return "\uf1f8"
        case "settings": return "\uf013"
        case "power": return "\uf011"
        case "sliders": return "\uf1de"
        case "equalizer": return "\ue473"
        case "infinity": return "\uf534"
        case "palette": return "\uf53f"
        case "image": return "\uf03e"
        case "keyboard": return "\uf11c"
        case "moon": return "\uf186"
        case "moodHappy": return "\uf118"
        case "moodSad": return "\uf5b4"
        case "moodBored": return "\uf11a"
        case "moodSuspense": return "\uf21b"
        case "moodMetal": return "\uf7a6"
        case "moodDance": return "\uf70c"
        case "sun": return "\uf185"
        case "lyrics": return "\uf10d"
        case "arrowUp": return "\uf062"
        case "arrowDown": return "\uf063"
        case "plus": return "\u002b"
        case "minus": return "\uf068"
        case "back": return "\uf060"
        case "cloud": return "\uf0c2"
        case "search": return "\uf002"
        case "bookmark": return "\uf02e"
        case "link": return "\uf0c1"
        case "user": return "\uf007"
        case "heart": return "\uf004"
        case "star": return "\uf005"
        case "compass": return "\uf14e"
        case "listMusic": return "\uf0ca"
        case "check": return "\uf00c"
        case "refresh": return "\uf021"
        case "more": return "\uf142"
        case "grip": return "\uf58e"
        case "chevronLeftSmall": return "\uf053"
        case "compactDisc": return "\uf51f"
        case "folder": return "\uf07b"
        case "folderPlus": return "\uf65e"
        case "eyeSlash": return "\uf070"
        case "home": return "\uf015"
        case "download": return "\uf019"
        case "drive": return "\uf0a0"
        default: return ""
        }
    }

    text: glyph(name)
    color: Theme.text
    font.family: "Font Awesome 6 Free"
    font.weight: Font.Black // the Solid face is weight 900
    font.pixelSize: size
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
}
