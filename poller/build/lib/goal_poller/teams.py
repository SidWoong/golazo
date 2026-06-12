"""2026 世界杯 48 强静态映射表与查询。

provider_team_id 不在此硬编码（无法离线核实），由 follow 流程通过
provider.list_teams() 按 name_en/tla/aliases 在线解析后写入 config。
名单核实于 2026-06-12（UEFA 官网 + Sky Sports）：欧洲区附加赛出线为
波黑/瑞典/土耳其/捷克，洲际附加赛出线为伊拉克/刚果民主共和国。
"""
from __future__ import annotations

# aliases 同时收录：中文别称、provider 侧可能使用的英文变体（用于 API 名称匹配）
TEAMS_WC2026: list[dict] = [
    # ── 亚足联 AFC (9) ──
    {"name_zh": "澳大利亚", "name_en": "Australia", "tla": "AUS", "flag": "🇦🇺", "aliases": ["澳洲", "袋鼠军团"]},
    {"name_zh": "伊朗", "name_en": "Iran", "tla": "IRN", "flag": "🇮🇷", "aliases": ["IR Iran"]},
    {"name_zh": "伊拉克", "name_en": "Iraq", "tla": "IRQ", "flag": "🇮🇶", "aliases": []},
    {"name_zh": "日本", "name_en": "Japan", "tla": "JPN", "flag": "🇯🇵", "aliases": ["蓝武士", "日本队"]},
    {"name_zh": "约旦", "name_en": "Jordan", "tla": "JOR", "flag": "🇯🇴", "aliases": []},
    {"name_zh": "卡塔尔", "name_en": "Qatar", "tla": "QAT", "flag": "🇶🇦", "aliases": ["卡達"]},
    {"name_zh": "沙特阿拉伯", "name_en": "Saudi Arabia", "tla": "KSA", "flag": "🇸🇦", "aliases": ["沙特", "沙地阿拉伯"]},
    {"name_zh": "韩国", "name_en": "South Korea", "tla": "KOR", "flag": "🇰🇷", "aliases": ["南韩", "大韩民国", "Korea Republic"]},
    {"name_zh": "乌兹别克斯坦", "name_en": "Uzbekistan", "tla": "UZB", "flag": "🇺🇿", "aliases": ["乌兹别克"]},
    # ── 非足联 CAF (10) ──
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
    # ── 中北美加勒比 CONCACAF (6，含三东道主) ──
    {"name_zh": "加拿大", "name_en": "Canada", "tla": "CAN", "flag": "🇨🇦", "aliases": []},
    {"name_zh": "库拉索", "name_en": "Curaçao", "tla": "CUW", "flag": "🇨🇼", "aliases": ["库拉索岛", "Curacao"]},
    {"name_zh": "海地", "name_en": "Haiti", "tla": "HAI", "flag": "🇭🇹", "aliases": []},
    {"name_zh": "墨西哥", "name_en": "Mexico", "tla": "MEX", "flag": "🇲🇽", "aliases": []},
    {"name_zh": "巴拿马", "name_en": "Panama", "tla": "PAN", "flag": "🇵🇦", "aliases": []},
    {"name_zh": "美国", "name_en": "United States", "tla": "USA", "flag": "🇺🇸", "aliases": ["美利坚", "USA", "USMNT"]},
    # ── 南美 CONMEBOL (6) ──
    {"name_zh": "阿根廷", "name_en": "Argentina", "tla": "ARG", "flag": "🇦🇷", "aliases": ["潘帕斯雄鹰", "蓝白军团"]},
    {"name_zh": "巴西", "name_en": "Brazil", "tla": "BRA", "flag": "🇧🇷", "aliases": ["桑巴军团", "五星巴西"]},
    {"name_zh": "哥伦比亚", "name_en": "Colombia", "tla": "COL", "flag": "🇨🇴", "aliases": []},
    {"name_zh": "厄瓜多尔", "name_en": "Ecuador", "tla": "ECU", "flag": "🇪🇨", "aliases": []},
    {"name_zh": "巴拉圭", "name_en": "Paraguay", "tla": "PAR", "flag": "🇵🇾", "aliases": []},
    {"name_zh": "乌拉圭", "name_en": "Uruguay", "tla": "URU", "flag": "🇺🇾", "aliases": []},
    # ── 大洋洲 OFC (1) ──
    {"name_zh": "新西兰", "name_en": "New Zealand", "tla": "NZL", "flag": "🇳🇿", "aliases": ["纽西兰"]},
    # ── 欧足联 UEFA (16) ──
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


def search(keyword: str) -> list[dict]:
    """模糊查询：关键词对 name_zh / name_en / tla / aliases 做大小写不敏感子串匹配。"""
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
    """把 provider 返回的球队名（英文）映射回静态表条目，用于解析 provider_team_id。"""
    name = api_name.strip().lower()
    for t in TEAMS_WC2026:
        if tla and t["tla"].lower() == tla.lower():
            return t
        candidates = [t["name_en"], *[a for a in t["aliases"] if a.isascii()]]
        if any(name == c.lower() for c in candidates):
            return t
    return None
