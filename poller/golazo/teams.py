"""Static mapping table of the 48 teams of World Cup 2026, plus lookups.

provider_team_id is deliberately not hardcoded here (it cannot be verified
offline); the follow flow resolves it online via provider.list_teams(),
matching on name_en/tla/aliases, and writes it into the config.
Roster verified on 2026-06-12 (UEFA official site + Sky Sports): the UEFA
play-off winners are Bosnia and Herzegovina / Sweden / Türkiye / Czechia,
the inter-confederation play-off winners are Iraq / DR Congo.
"""
from __future__ import annotations

# aliases hold both Chinese nicknames and English variants the provider may use (for API name matching)
TEAMS_WC2026: list[dict] = [
    # ── AFC (9) ──
    {"name_zh": "澳大利亚", "name_en": "Australia", "tla": "AUS", "flag": "🇦🇺", "aliases": ["澳洲", "袋鼠军团"]},
    {"name_zh": "伊朗", "name_en": "Iran", "tla": "IRN", "flag": "🇮🇷", "aliases": ["IR Iran"]},
    {"name_zh": "伊拉克", "name_en": "Iraq", "tla": "IRQ", "flag": "🇮🇶", "aliases": []},
    {"name_zh": "日本", "name_en": "Japan", "tla": "JPN", "flag": "🇯🇵", "aliases": ["蓝武士", "日本队"]},
    {"name_zh": "约旦", "name_en": "Jordan", "tla": "JOR", "flag": "🇯🇴", "aliases": []},
    {"name_zh": "卡塔尔", "name_en": "Qatar", "tla": "QAT", "flag": "🇶🇦", "aliases": ["卡達"]},
    {"name_zh": "沙特阿拉伯", "name_en": "Saudi Arabia", "tla": "KSA", "flag": "🇸🇦", "aliases": ["沙特", "沙地阿拉伯"]},
    {"name_zh": "韩国", "name_en": "South Korea", "tla": "KOR", "flag": "🇰🇷", "aliases": ["南韩", "大韩民国", "Korea Republic"]},
    {"name_zh": "乌兹别克斯坦", "name_en": "Uzbekistan", "tla": "UZB", "flag": "🇺🇿", "aliases": ["乌兹别克"]},
    # ── CAF (10) ──
    {"name_zh": "阿尔及利亚", "name_en": "Algeria", "tla": "ALG", "flag": "🇩🇿", "aliases": []},
    {"name_zh": "佛得角", "name_en": "Cape Verde", "tla": "CPV", "flag": "🇨🇻", "aliases": ["维德角", "Cabo Verde", "Cape Verde Islands"]},
    {"name_zh": "刚果民主共和国", "name_en": "DR Congo", "tla": "COD", "flag": "🇨🇩", "aliases": ["刚果（金）", "刚果金", "民主刚果", "Congo DR", "Congo, Democratic Republic"]},
    {"name_zh": "埃及", "name_en": "Egypt", "tla": "EGY", "flag": "🇪🇬", "aliases": ["法老军团"]},
    {"name_zh": "加纳", "name_en": "Ghana", "tla": "GHA", "flag": "🇬🇭", "aliases": []},
    {"name_zh": "科特迪瓦", "name_en": "Ivory Coast", "tla": "CIV", "flag": "🇨🇮", "aliases": ["象牙海岸", "Côte d'Ivoire", "Cote d'Ivoire"]},
    {"name_zh": "摩洛哥", "name_en": "Morocco", "tla": "MAR", "flag": "🇲🇦", "aliases": []},
    {"name_zh": "塞内加尔", "name_en": "Senegal", "tla": "SEN", "flag": "🇸🇳", "aliases": []},
    {"name_zh": "南非", "name_en": "South Africa", "tla": "RSA", "flag": "🇿🇦", "aliases": []},
    {"name_zh": "突尼斯", "name_en": "Tunisia", "tla": "TUN", "flag": "🇹🇳", "aliases": ["突尼西亚"]},
    # ── CONCACAF (6, incl. the three hosts) ──
    {"name_zh": "加拿大", "name_en": "Canada", "tla": "CAN", "flag": "🇨🇦", "aliases": []},
    {"name_zh": "库拉索", "name_en": "Curaçao", "tla": "CUW", "flag": "🇨🇼", "aliases": ["库拉索岛", "Curacao"]},
    {"name_zh": "海地", "name_en": "Haiti", "tla": "HAI", "flag": "🇭🇹", "aliases": []},
    {"name_zh": "墨西哥", "name_en": "Mexico", "tla": "MEX", "flag": "🇲🇽", "aliases": []},
    {"name_zh": "巴拿马", "name_en": "Panama", "tla": "PAN", "flag": "🇵🇦", "aliases": []},
    {"name_zh": "美国", "name_en": "United States", "tla": "USA", "flag": "🇺🇸", "aliases": ["美利坚", "USA", "USMNT"]},
    # ── CONMEBOL (6) ──
    {"name_zh": "阿根廷", "name_en": "Argentina", "tla": "ARG", "flag": "🇦🇷", "aliases": ["潘帕斯雄鹰", "蓝白军团"]},
    {"name_zh": "巴西", "name_en": "Brazil", "tla": "BRA", "flag": "🇧🇷", "aliases": ["桑巴军团", "五星巴西"]},
    {"name_zh": "哥伦比亚", "name_en": "Colombia", "tla": "COL", "flag": "🇨🇴", "aliases": []},
    {"name_zh": "厄瓜多尔", "name_en": "Ecuador", "tla": "ECU", "flag": "🇪🇨", "aliases": []},
    {"name_zh": "巴拉圭", "name_en": "Paraguay", "tla": "PAR", "flag": "🇵🇾", "aliases": []},
    {"name_zh": "乌拉圭", "name_en": "Uruguay", "tla": "URU", "flag": "🇺🇾", "aliases": []},
    # ── OFC (1) ──
    {"name_zh": "新西兰", "name_en": "New Zealand", "tla": "NZL", "flag": "🇳🇿", "aliases": ["纽西兰"]},
    # ── UEFA (16) ──
    {"name_zh": "奥地利", "name_en": "Austria", "tla": "AUT", "flag": "🇦🇹", "aliases": []},
    {"name_zh": "比利时", "name_en": "Belgium", "tla": "BEL", "flag": "🇧🇪", "aliases": ["欧洲红魔"]},
    {"name_zh": "波黑", "name_en": "Bosnia and Herzegovina", "tla": "BIH", "flag": "🇧🇦", "aliases": ["波斯尼亚和黑塞哥维那", "波斯尼亚", "Bosnia-Herzegovina"]},
    {"name_zh": "克罗地亚", "name_en": "Croatia", "tla": "CRO", "flag": "🇭🇷", "aliases": ["格子军团"]},
    {"name_zh": "捷克", "name_en": "Czechia", "tla": "CZE", "flag": "🇨🇿", "aliases": ["捷克共和国", "Czech Republic"]},
    {"name_zh": "英格兰", "name_en": "England", "tla": "ENG", "flag": "🏴󠁧󠁢󠁥󠁮󠁧󠁿", "aliases": ["英国", "三狮军团"]},
    {"name_zh": "法国", "name_en": "France", "tla": "FRA", "flag": "🇫🇷", "aliases": ["高卢雄鸡", "法兰西"]},
    {"name_zh": "德国", "name_en": "Germany", "tla": "GER", "flag": "🇩🇪", "aliases": ["德意志", "日耳曼战车"]},
    {"name_zh": "荷兰", "name_en": "Netherlands", "tla": "NED", "flag": "🇳🇱", "aliases": ["尼德兰", "橙衣军团", "Holland"]},
    {"name_zh": "挪威", "name_en": "Norway", "tla": "NOR", "flag": "🇳🇴", "aliases": []},
    {"name_zh": "葡萄牙", "name_en": "Portugal", "tla": "POR", "flag": "🇵🇹", "aliases": ["五盾军团"]},
    {"name_zh": "苏格兰", "name_en": "Scotland", "tla": "SCO", "flag": "🏴󠁧󠁢󠁳󠁣󠁴󠁿", "aliases": []},
    {"name_zh": "西班牙", "name_en": "Spain", "tla": "ESP", "flag": "🇪🇸", "aliases": ["斗牛士军团"]},
    {"name_zh": "瑞典", "name_en": "Sweden", "tla": "SWE", "flag": "🇸🇪", "aliases": []},
    {"name_zh": "瑞士", "name_en": "Switzerland", "tla": "SUI", "flag": "🇨🇭", "aliases": []},
    {"name_zh": "土耳其", "name_en": "Türkiye", "tla": "TUR", "flag": "🇹🇷", "aliases": ["Turkey", "土耳其共和国"]},
]


# Home-kit colors per team (jersey body / stripe accent / shorts), used by the overlay to dress the runner
KITS: dict[str, tuple[str, str, str]] = {
    "AUS": ("#ffcd00", "#00843d", "#00843d"), "IRN": ("#ffffff", "#da0000", "#ffffff"),
    "IRQ": ("#007a3d", "#ffffff", "#ffffff"), "JPN": ("#1d2088", "#ffffff", "#ffffff"),
    "JOR": ("#ce1126", "#ffffff", "#ffffff"), "QAT": ("#8a1538", "#ffffff", "#8a1538"),
    "KSA": ("#ffffff", "#006c35", "#ffffff"), "KOR": ("#cd2e3a", "#0f64cd", "#1a1a1a"),
    "UZB": ("#ffffff", "#0099b5", "#0099b5"),
    "ALG": ("#ffffff", "#006233", "#ffffff"), "CPV": ("#003893", "#cf2027", "#ffffff"),
    "COD": ("#0085ca", "#fdd116", "#0085ca"), "EGY": ("#ce1126", "#ffffff", "#1a1a1a"),
    "GHA": ("#ffffff", "#000000", "#1a1a1a"), "CIV": ("#ff8200", "#ffffff", "#ffffff"),
    "MAR": ("#c1272d", "#006233", "#006233"), "SEN": ("#ffffff", "#00853f", "#ffffff"),
    "RSA": ("#ffb612", "#007749", "#007749"), "TUN": ("#e70013", "#ffffff", "#ffffff"),
    "CAN": ("#d80621", "#ffffff", "#d80621"), "CUW": ("#002b7f", "#f9e814", "#002b7f"),
    "HAI": ("#00209f", "#d21034", "#d21034"), "MEX": ("#006847", "#ffffff", "#ffffff"),
    "PAN": ("#d21034", "#ffffff", "#d21034"), "USA": ("#ffffff", "#002868", "#002868"),
    "ARG": ("#74acdf", "#ffffff", "#1a1a2e"), "BRA": ("#ffdc02", "#009b3a", "#002776"),
    "COL": ("#fcd116", "#003893", "#003893"), "ECU": ("#ffd100", "#0033a0", "#0033a0"),
    "PAR": ("#d52b1e", "#ffffff", "#0038a8"), "URU": ("#6fb1e0", "#ffffff", "#1a1a1a"),
    "NZL": ("#ffffff", "#000000", "#1a1a1a"),
    "AUT": ("#ed2939", "#ffffff", "#ed2939"), "BEL": ("#e30613", "#1a1a1a", "#e30613"),
    "BIH": ("#002f6c", "#fecb00", "#002f6c"), "CRO": ("#e63946", "#ffffff", "#ffffff"),
    "CZE": ("#d7141a", "#ffffff", "#ffffff"), "ENG": ("#ffffff", "#002366", "#002366"),
    "FRA": ("#002654", "#ffffff", "#ffffff"), "GER": ("#ffffff", "#000000", "#1a1a1a"),
    "NED": ("#ff7f00", "#ffffff", "#ffffff"), "NOR": ("#c8102e", "#ffffff", "#00205b"),
    "POR": ("#9e1b32", "#046a38", "#046a38"), "SCO": ("#003078", "#ffffff", "#ffffff"),
    "ESP": ("#aa151b", "#f1bf00", "#002496"), "SWE": ("#ffcd00", "#004b87", "#004b87"),
    "SUI": ("#d52b1e", "#ffffff", "#ffffff"), "TUR": ("#e30a17", "#ffffff", "#ffffff"),
}


def kit_for(entry: dict | None) -> dict | None:
    """Static-table entry → kit dict (written into state.json event.kit). None for unknown teams."""
    if not entry:
        return None
    k = KITS.get(entry.get("tla", ""))
    if not k:
        return None
    return {"jersey": k[0], "stripe": k[1], "shorts": k[2]}


def search(keyword: str) -> list[dict]:
    """Fuzzy lookup: case-insensitive substring match against name_zh / name_en / tla / aliases."""
    kw = keyword.strip().lower()
    if not kw:
        return []
    hits = []
    for t in TEAMS_WC2026:
        haystack = [t["name_zh"], t["name_en"], t["tla"], *t["aliases"]]
        if any(kw in s.lower() or s.lower() in kw for s in haystack if s):
            hits.append(t)
    return hits


def match_api_name(api_name: str, tla: str | None = None) -> dict | None:
    """Map a provider-side (English) team name back to a static-table entry, used to resolve provider_team_id."""
    name = api_name.strip().lower()
    for t in TEAMS_WC2026:
        if tla and t["tla"].lower() == tla.lower():
            return t
        candidates = [t["name_en"], *[a for a in t["aliases"] if a.isascii()]]
        if any(name == c.lower() for c in candidates):
            return t
    return None
