"""
Flask entry point for NSE Catalyst Scanner.
Runs on Render (free tier), Railway, PythonAnywhere, or locally.
Routes: / (dashboard), /manage, /search, /add, /remove, /rebuild
REST API: /api/stocks, /api/events, /api/stock/<ticker>, /api/search, /api/watchlist, /api/health
"""
import os, sys, subprocess, json
from flask import Flask, request, jsonify, redirect, send_from_directory

# Works on any server — always resolves relative to this file's location
SCANNER_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCANNER_DIR)
import catalyst_core as core

app = Flask(__name__)


@app.route("/")
def index():
    return send_from_directory(os.path.join(SCANNER_DIR, "site"), "index.html")


def _python_exe():
    """Return the right python executable — works on Render, PA, local."""
    return sys.executable or "python3"


@app.route("/rebuild")
def rebuild():
    result = subprocess.run(
        [_python_exe(), "build_dashboard.py"],
        cwd=SCANNER_DIR, capture_output=True, text=True
    )
    out = (result.stdout or "") + (result.stderr or "")
    if result.returncode == 0:
        return ('<h2 style="font-family:sans-serif;color:#4caf7d">Rebuilt OK</h2>'
                '<pre style="font-family:monospace;font-size:12px">' + out[-2000:] + '</pre>'
                '<a href="/" style="font-family:sans-serif">View dashboard</a>')
    return ("<h2 style='font-family:sans-serif;color:#e05c5c'>Build failed</h2>"
            "<pre style='font-family:monospace;font-size:12px'>" + out[-3000:] + "</pre>")

_NSE_STOCKS = [
    ("360ONE","360 ONE WAM"),("3MINDIA","3M India"),("ABB","ABB India"),
    ("ACC","ACC"),("ACMESOLAR","ACME Solar"),("AIAENG","AIA Engineering"),
    ("APLAPOLLO","APL Apollo Tubes"),("AUBANK","AU Small Finance Bank"),("AWL","AWL Agri Business"),
    ("AADHARHFC","Aadhar Housing Finance"),("AARTIIND","Aarti Industries"),("AAVAS","Aavas Financiers"),
    ("ABBOTINDIA","Abbott India"),("ACE","Action Construction Equipment"),("ADANIENSOL","Adani Energy Solutions"),
    ("ADANIENT","Adani Enterprises"),("ADANIGREEN","Adani Green Energy"),("ADANIPORTS","Adani Ports"),
    ("ADANIPOWER","Adani Power"),("ATGL","Adani Total Gas"),("ABCAPITAL","Aditya Birla Capital"),
    ("ABFRL","Aditya Birla Fashion"),("ABSLAMC","Aditya Birla Sun Life AMC"),("AEGISLOG","Aegis Logistics"),
    ("AFCONS","Afcons Infrastructure"),("AFFLE","Affle"),("AJANTPHARM","Ajanta Pharma"),
    ("AKZOINDIA","Akzo Nobel India"),("ALKEM","Alkem Laboratories"),("ARE&M","Amara Raja Energy"),
    ("AMBER","Amber Enterprises"),("AMBUJACEM","Ambuja Cements"),("ANANDRATHI","Anand Rathi Wealth"),
    ("ANANTRAJ","Anant Raj"),("ANGELONE","Angel One"),("ANURAS","Anupam Rasayan"),
    ("APARINDS","Apar Industries"),("APOLLOHOSP","Apollo Hospitals"),("APOLLOTYRE","Apollo Tyres"),
    ("APTUS","Aptus Value Housing Finance"),("ASAHIINDIA","Asahi India Glass"),("ASHOKLEY","Ashok Leyland"),
    ("ASIANPAINT","Asian Paints"),("ASTERDM","Aster DM Healthcare"),("ASTRAL","Astral"),
    ("ATHERENERG","Ather Energy"),("ATUL","Atul"),("AUROPHARMA","Aurobindo Pharma"),
    ("AIIL","Authum Investment"),("DMART","Avenue Supermarts"),("AXISBANK","Axis Bank"),
    ("BEML","BEML"),("BLS","BLS International"),("BSE","BSE"),
    ("BAJAJ-AUTO","Bajaj Auto"),("BAJFINANCE","Bajaj Finance"),("BAJAJFINSV","Bajaj Finserv"),
    ("BAJAJHLDNG","Bajaj Holdings"),("BAJAJHFL","Bajaj Housing Finance"),("BALKRISIND","Balkrishna Industries"),
    ("BALRAMCHIN","Balrampur Chini Mills"),("BANDHANBNK","Bandhan Bank"),("BANKBARODA","Bank of Baroda"),
    ("BANKINDIA","Bank of India"),("MAHABANK","Bank of Maharashtra"),("BATAINDIA","Bata India"),
    ("BAYERCROP","Bayer Cropscience"),("BERGEPAINT","Berger Paints"),("BDL","Bharat Dynamics"),
    ("BEL","Bharat Electronics"),("BHARATFORG","Bharat Forge"),("BHEL","Bharat Heavy Electricals"),
    ("BPCL","BPCL"),("BHARTIARTL","Bharti Airtel"),("BHARTIHEXA","Bharti Hexacom"),
    ("BIKAJI","Bikaji Foods"),("GROWW","Billionbrains Garage (Groww)"),("BIOCON","Biocon"),
    ("BSOFT","Birlasoft"),("BLUEDART","Blue Dart Express"),("BLUEJET","Blue Jet Healthcare"),
    ("BLUESTARCO","Blue Star"),("BOSCHLTD","Bosch"),("FIRSTCRY","Brainbees (FirstCry)"),
    ("BRIGADE","Brigade Enterprises"),("BRITANNIA","Britannia Industries"),("MAPMYINDIA","C.E. Info Systems (MapMyIndia)"),
    ("CCL","CCL Products"),("CESC","CESC"),("CGPOWER","CG Power"),
    ("CRISIL","CRISIL"),("CANFINHOME","Can Fin Homes"),("CANBK","Canara Bank"),
    ("CANHLIFE","Canara HSBC Life Insurance"),("CAPLIPOINT","Caplin Point Laboratories"),("CARBORUNIV","Carborundum Universal"),
    ("CASTROLIND","Castrol India"),("CEATLTD","CEAT"),("CENTRALBK","Central Bank of India"),
    ("CDSL","CDSL"),("CHALET","Chalet Hotels"),("CHAMBLFERT","Chambal Fertilisers"),
    ("CHENNPETRO","Chennai Petroleum"),("CHOLAFIN","Cholamandalam Finance"),("CIPLA","Cipla"),
    ("CUB","City Union Bank"),("CLEAN","Clean Science and Technology"),("COALINDIA","Coal India"),
    ("COCHINSHIP","Cochin Shipyard"),("COFORGE","Coforge"),("COLPAL","Colgate-Palmolive"),
    ("CAMS","CAMS"),("CONCORDBIO","Concord Biotech"),("CONCOR","Container Corporation of India"),
    ("COROMANDEL","Coromandel International"),("CROMPTON","Crompton Greaves Consumer"),("CUMMINSIND","Cummins India"),
    ("CYIENT","Cyient"),("DLF","DLF"),("DOMS","DOMS Industries"),
    ("DABUR","Dabur India"),("DALBHARAT","Dalmia Bharat"),("DATAPATTNS","Data Patterns"),
    ("DEEPAKFERT","Deepak Fertilisers"),("DEEPAKNTR","Deepak Nitrite"),("DELHIVERY","Delhivery"),
    ("DEVYANI","Devyani International"),("DIVISLAB","Divi's Laboratories"),("DIXON","Dixon Technologies"),
    ("LALPATHLAB","Dr. Lal Path Labs"),("DRREDDY","Dr. Reddy's Laboratories"),("EIHOTEL","EIH Hotels"),
    ("EICHERMOT","Eicher Motors"),("ELECON","Elecon Engineering"),("ELGIEQUIP","Elgi Equipments"),
    ("EMAMILTD","Emami"),("EMCURE","Emcure Pharmaceuticals"),("ENDURANCE","Endurance Technologies"),
    ("ENGINERSIN","Engineers India"),("ERIS","Eris Lifesciences"),("ESCORTS","Escorts Kubota"),
    ("ETERNAL","Eternal (Zomato)"),("EXIDEIND","Exide Industries"),("NYKAA","FSN E-Commerce (Nykaa)"),
    ("FEDERALBNK","Federal Bank"),("FACT","FACT"),("FINCABLES","Finolex Cables"),
    ("FSL","Firstsource Solutions"),("FIVESTAR","Five-Star Business Finance"),("FORCEMOT","Force Motors"),
    ("FORTIS","Fortis Healthcare"),("GAIL","GAIL"),("GMRAIRPORT","GMR Airports"),
    ("GRSE","Garden Reach Shipbuilders"),("GICRE","General Insurance Corporation"),("GILLETTE","Gillette India"),
    ("GLAND","Gland Pharma"),("GLAXO","GSK Pharma"),("GLENMARK","Glenmark Pharma"),
    ("MEDANTA","Global Health (Medanta)"),("GODIGIT","Go Digit Insurance"),("GODFRYPHLP","Godfrey Phillips"),
    ("GODREJCP","Godrej Consumer"),("GODREJIND","Godrej Industries"),("GODREJPROP","Godrej Properties"),
    ("GRANULES","Granules India"),("GRAPHITE","Graphite India"),("GRASIM","Grasim Industries"),
    ("GRAVITA","Gravita India"),("GESHIP","Great Eastern Shipping"),("FLUOROCHEM","Gujarat Fluorochemicals"),
    ("GMDCLTD","GMDC"),("GSPL","Gujarat State Petronet"),("HEG","H.E.G."),
    ("HCLTECH","HCL Technologies"),("HDBFS","HDB Financial Services"),("HDFCAMC","HDFC AMC"),
    ("HDFCBANK","HDFC Bank"),("HDFCLIFE","HDFC Life Insurance"),("HFCL","HFCL"),
    ("HAVELLS","Havells India"),("HEROMOTOCO","Hero MotoCorp"),("HEXT","Hexaware Technologies"),
    ("HSCL","Himadri Speciality Chemical"),("HINDALCO","Hindalco Industries"),("HAL","Hindustan Aeronautics"),
    ("HINDCOPPER","Hindustan Copper"),("HINDPETRO","Hindustan Petroleum"),("HINDUNILVR","Hindustan Unilever"),
    ("HINDZINC","Hindustan Zinc"),("POWERINDIA","Hitachi Energy India"),("HOMEFIRST","Home First Finance"),
    ("HONASA","Honasa Consumer"),("HONAUT","Honeywell Automation India"),("HUDCO","HUDCO"),
    ("HYUNDAI","Hyundai Motor India"),("ICICIBANK","ICICI Bank"),("ICICIGI","ICICI Lombard General Insurance"),
    ("ICICIAMC","ICICI Prudential AMC"),("ICICIPRULI","ICICI Prudential Life Insurance"),("IDBI","IDBI Bank"),
    ("IDFCFIRSTB","IDFC First Bank"),("IIFL","IIFL Finance"),("IRB","IRB Infrastructure"),
    ("IRCON","IRCON International"),("ITC","ITC"),("IRCTC","IRCTC"),
    ("IRFC","Indian Railway Finance"),("IREDA","IREDA"),("IGL","Indraprastha Gas"),
    ("INDUSTOWER","Indus Towers"),("INDUSINDBK","IndusInd Bank"),("NAUKRI","Info Edge (Naukri)"),
    ("INFY","Infosys"),("INOXWIND","Inox Wind"),("INTELLECT","Intellect Design Arena"),
    ("INDIGO","IndiGo (InterGlobe Aviation)"),("IKS","Inventurus Knowledge Solutions"),("IPCALAB","IPCA Laboratories"),
    ("JBCHEPHARM","J.B. Chemicals & Pharma"),("JKCEMENT","J.K. Cement"),("JBMA","JBM Auto"),
    ("JKTYRE","JK Tyre"),("JMFINANCIL","JM Financial"),("JSWCEMENT","JSW Cement"),
    ("JSWENERGY","JSW Energy"),("JSWINFRA","JSW Infrastructure"),("JSWSTEEL","JSW Steel"),
    ("JPPOWER","Jaiprakash Power"),("JINDALSTEL","Jindal Steel"),("JIOFIN","Jio Financial Services"),
    ("JUBLFOOD","Jubilant Foodworks"),("JUBLINGREA","Jubilant Ingrevia"),("JUBLPHARMA","Jubilant Pharmova"),
    ("JWL","Jupiter Wagons"),("JYOTICNC","Jyoti CNC Automation"),("KPRMILL","K.P.R. Mill"),
    ("KEI","KEI Industries"),("KPITTECH","KPIT Technologies"),("KAJARIACER","Kajaria Ceramics"),
    ("KPIL","Kalpataru Projects"),("KALYANKJIL","Kalyan Jewellers"),("KARURVYSYA","Karur Vysya Bank"),
    ("KAYNES","Kaynes Technology"),("KEC","KEC International"),("KFINTECH","KFin Technologies"),
    ("KOTAKBANK","Kotak Mahindra Bank"),("KIMS","Krishna Institute of Medical Sciences"),("LTF","L&T Finance"),
    ("LTTS","L&T Technology Services"),("LGEINDIA","LG Electronics India"),("LICHSGFIN","LIC Housing Finance"),
    ("LTM","LTIMindtree"),("LT","Larsen & Toubro"),("LATENTVIEW","Latent View Analytics"),
    ("LAURUSLABS","Laurus Labs"),("LEMONTREE","Lemon Tree Hotels"),("LICI","Life Insurance Corporation"),
    ("LINDEINDIA","Linde India"),("LLOYDSME","Lloyds Metals"),("LODHA","Lodha Developers"),
    ("LUPIN","Lupin"),("MRF","MRF"),("MGL","Mahanagar Gas"),
    ("M&MFIN","Mahindra & Mahindra Financial"),("M&M","Mahindra & Mahindra"),("MANAPPURAM","Manappuram Finance"),
    ("MRPL","Mangalore Refinery"),("MANKIND","Mankind Pharma"),("MARICO","Marico"),
    ("MARUTI","Maruti Suzuki"),("MFSL","Max Financial Services"),("MAXHEALTH","Max Healthcare"),
    ("MAZDOCK","Mazagon Dock Shipbuilders"),("MEESHO","Meesho"),("MINDACORP","Minda Corporation"),
    ("MOTHERSON","Samvardhana Motherson"),("MOTILALOFS","Motilal Oswal Financial"),("MPHASIS","MphasiS"),
    ("MCX","Multi Commodity Exchange"),("MUTHOOTFIN","Muthoot Finance"),("NATCOPHARM","NATCO Pharma"),
    ("NBCC","NBCC"),("NCC","NCC"),("NHPC","NHPC"),
    ("NLCINDIA","NLC India"),("NMDC","NMDC"),("NTPC","NTPC"),
    ("NTPCGREEN","NTPC Green Energy"),("NH","Narayana Hrudayalaya"),("NATIONALUM","National Aluminium"),
    ("NAVINFLUOR","Navin Fluorine International"),("NESTLEIND","Nestle India"),("NETWEB","Netweb Technologies"),
    ("NEULANDLAB","Neuland Laboratories"),("NEWGEN","Newgen Software"),("NAM-INDIA","Nippon Life India AMC"),
    ("NIVABUPA","Niva Bupa Health Insurance"),("NUVAMA","Nuvama Wealth"),("OBEROIRLTY","Oberoi Realty"),
    ("ONGC","ONGC"),("OIL","Oil India"),("OLAELEC","Ola Electric"),
    ("OLECTRA","Olectra Greentech"),("PAYTM","Paytm"),("OFSS","Oracle Financial Services"),
    ("POLICYBZR","PB Fintech (PolicyBazaar)"),("PCBL","PCBL Chemical"),("PGEL","PG Electroplast"),
    ("PIIND","PI Industries"),("PNBHOUSING","PNB Housing Finance"),("PVRINOX","PVR INOX"),
    ("PAGEIND","Page Industries"),("PARADEEP","Paradeep Phosphates"),("PATANJALI","Patanjali Foods"),
    ("PERSISTENT","Persistent Systems"),("PETRONET","Petronet LNG"),("PFIZER","Pfizer India"),
    ("PHOENIXLTD","Phoenix Mills"),("PIDILITIND","Pidilite Industries"),("PIRAMALFIN","Piramal Finance"),
    ("PPLPHARMA","Piramal Pharma"),("POLYMED","Poly Medicure"),("POLYCAB","Polycab India"),
    ("POONAWALLA","Poonawalla Fincorp"),("PFC","Power Finance Corporation"),("POWERGRID","Power Grid"),
    ("PREMIERENE","Premier Energies"),("PRESTIGE","Prestige Estates"),("PNB","Punjab National Bank"),
    ("RRKABEL","R R Kabel"),("RBLBANK","RBL Bank"),("RECLTD","REC"),
    ("RITES","RITES"),("RADICO","Radico Khaitan"),("RVNL","Rail Vikas Nigam"),
    ("RAILTEL","RailTel Corporation"),("RAINBOW","Rainbow Childrens Medicare"),("RKFORGE","Ramkrishna Forgings"),
    ("REDINGTON","Redington"),("RELIANCE","Reliance Industries"),("RPOWER","Reliance Power"),
    ("SBICARD","SBI Cards"),("SBILIFE","SBI Life Insurance"),("SJVN","SJVN"),
    ("SRF","SRF"),("SAIL","Steel Authority of India"),("SBIN","State Bank of India"),
    ("SOLARINDS","Solar Industries India"),("SONACOMS","Sona BLW Precision"),("SONATSOFTW","Sonata Software"),
    ("STARHEALTH","Star Health Insurance"),("SUMICHEM","Sumitomo Chemical India"),("SUNPHARMA","Sun Pharma"),
    ("SUNTV","Sun TV Network"),("SUNDARMFIN","Sundaram Finance"),("SUPREMEIND","Supreme Industries"),
    ("SUZLON","Suzlon Energy"),("SWIGGY","Swiggy"),("SYNGENE","Syngene International"),
    ("SYRMA","Syrma SGS Technology"),("TBOTEK","TBO Tek"),("TVSMOTOR","TVS Motor"),
    ("TATACHEM","Tata Chemicals"),("TATACOMM","Tata Communications"),("TCS","Tata Consultancy Services"),
    ("TATACONSUM","Tata Consumer Products"),("TATAELXSI","Tata Elxsi"),("TATAINVEST","Tata Investment Corporation"),
    ("TMPV","Tata Motors Passenger Vehicles"),("TATAPOWER","Tata Power"),("TATASTEEL","Tata Steel"),
    ("TATATECH","Tata Technologies"),("TECHM","Tech Mahindra"),("THERMAX","Thermax"),
    ("TIMKEN","Timken India"),("TITAGARH","Titagarh Rail Systems"),("TITAN","Titan Company"),
    ("TORNTPHARM","Torrent Pharma"),("TORNTPOWER","Torrent Power"),("TRENT","Trent"),
    ("TRIDENT","Trident"),("TRITURBINE","Triveni Turbine"),("TIINDIA","Tube Investments"),
    ("UCOBANK","UCO Bank"),("UNOMINDA","UNO Minda"),("UPL","UPL"),
    ("UTIAMC","UTI AMC"),("ULTRACEMCO","UltraTech Cement"),("UNIONBANK","Union Bank of India"),
    ("UBL","United Breweries"),("UNITDSPR","United Spirits"),("USHAMART","Usha Martin"),
    ("VTL","Vardhman Textiles"),("VBL","Varun Beverages"),("VEDL","Vedanta"),
    ("VMM","Vishal Mega Mart"),("IDEA","Vodafone Idea"),("VOLTAS","Voltas"),
    ("WAAREEENER","Waaree Energies"),("WELCORP","Welspun Corp"),("WELSPUNLIV","Welspun Living"),
    ("WHIRLPOOL","Whirlpool India"),("WIPRO","Wipro"),("WOCKPHARMA","Wockhardt"),
    ("YESBANK","Yes Bank"),("ZEEL","Zee Entertainment"),("ZENTEC","Zen Technologies"),
    ("ZENSARTECH","Zensar Technologies"),("ZYDUSLIFE","Zydus Lifesciences"),("ZYDUSWELL","Zydus Wellness"),
    ("JSLL","Jeena Sikho Lifecare"),("ECLERX","eClerx Services"),("CHOLAHLDNG","Cholamandalam Financial Holdings"),("CGCL","Capri Global Capital"),
    ("CREDITACC","CreditAccess Grameen"),("JAINREC","Jain Resource Recycling"),("GALLANTT","Gallantt Ispat"),
    ("CRAFTSMAN","Craftsman Automation"),("GPIL","Godawari Power & Ispat"),("ABLBL","Aditya Birla Lifestyle Brands"),
    ("ABREL","Aditya Birla Real Estate"),("AEGISVOPAK","Aegis Vopak Terminals"),("ACUTAAS","Acutaas Chemicals"),
    ("NSLNISP","NMDC Steel"),("INDIAMART","IndiaMART"),("SBFC","SBFC Finance"),
    ("TATACAP","Tata Capital"),("TMCV","Tata Motors CV"),("MSUMI","Motherson Sumi Wiring"),
    ("LENSKART","Lenskart"),("THELEELA","The Leela Hotels"),("PWL","PhysicsWallah"),
    ("SAGILITY","Sagility"),("SAILIFE","Sai Life Sciences"),("SAMMAANCAP","Sammaan Capital"),
    ("SAPPHIRE","Sapphire Foods"),("SARDAEN","Sarda Energy"),("SAREGAMA","Saregama"),
    ("SCHAEFFLER","Schaeffler India"),("SCHNEIDER","Schneider Electric"),("SCI","Shipping Corporation of India"),
    ("SHREECEM","Shree Cement"),("SHRIRAMFIN","Shriram Finance"),("SHYAMMETL","Shyam Metalics"),
    ("SIEMENS","Siemens"),("SIGNATURE","Signatureglobal"),("SOBHA","Sobha"),
    ("CARTRADE","CarTrade Tech"),("IEX","Indian Energy Exchange"),("NIACL","New India Assurance"),
    ("INDHOTEL","Indian Hotels (Taj)"),("JUSTDIAL","Just Dial"),
]


@app.route("/search")
def search():
    q = request.args.get("q", "").strip().lower()
    if len(q) < 2:
        return jsonify([])
    core.reload_stocks()
    results = []
    seen = set()
    for ticker, name in _NSE_STOCKS:
        if ticker in seen:
            continue
        if q in ticker.lower() or q in name.lower():
            results.append({"ticker": ticker, "name": name, "added": ticker in core.STOCKS})
            seen.add(ticker)
        if len(results) >= 8:
            break
    return jsonify(results)


@app.route("/add", methods=["POST"])
def add():
    ticker = request.form.get("ticker", "").upper().strip()
    display_name = request.form.get("name", "").strip() or None
    if not ticker:
        return redirect("/manage?error=No+ticker+provided")
    try:
        core.reload_stocks()
        core.add_stock(ticker, display_name=display_name)
    except Exception as e:
        return redirect("/manage?error=" + str(e).replace(" ", "+")[:120])
    ok, err = _rebuild_sync()
    if err:
        return redirect("/manage?error=Added+" + ticker + "+but+rebuild+failed:+" + err[:80].replace(" ", "+"))
    return redirect("/manage?ok=Added+" + ticker + "+and+dashboard+rebuilt")


@app.route("/remove", methods=["POST"])
def remove():
    ticker = request.form.get("ticker", "").upper().strip()
    try:
        core.reload_stocks()
        core.remove_stock(ticker)
    except Exception as e:
        return redirect("/manage?error=" + str(e).replace(" ", "+")[:120])
    ok, err = _rebuild_sync()
    if err:
        return redirect("/manage?error=Removed+" + ticker + "+but+rebuild+failed:+" + err[:80].replace(" ", "+"))
    return redirect("/manage?ok=Removed+" + ticker + "+and+dashboard+rebuilt")


def _rebuild_sync():
    try:
        result = subprocess.run(
            [_python_exe(), "build_dashboard.py"],
            cwd=SCANNER_DIR, capture_output=True, text=True, timeout=120,
        )
        if result.returncode == 0:
            return True, None
        err = (result.stderr or result.stdout or "unknown error")[-200:]
        return False, err
    except Exception as e:
        return False, str(e)

_MANAGE_HTML = (
    "<!doctype html><html lang='en'><head>"
    "<meta charset='utf-8'>"
    "<meta name='viewport' content='width=device-width,initial-scale=1'>"
    "<title>Manage Stocks - NSE Catalyst Scanner</title>"
    "<style>"
    "body{margin:0;font-family:-apple-system,Segoe UI,Roboto,sans-serif;background:#0b1220;color:#e7ecf6;}"
    "a{color:#4f8cff;text-decoration:none;}"
    "h1{font-size:20px;margin:0 0 4px;}"
    ".sub{color:#93a1bd;font-size:13px;margin-bottom:28px;}"
    ".card{background:#121a2c;border:1px solid #243049;border-radius:14px;padding:22px 24px;margin-bottom:24px;}"
    "table{width:100%;border-collapse:collapse;}"
    "tr:not(:last-child) td{border-bottom:1px solid #1c2a4a;}"
    "input[type=text]{background:#0b1220;border:1px solid #4f8cff66;color:#e7ecf6;"
    "padding:10px 14px;border-radius:8px;font-size:15px;width:calc(100% - 110px);outline:none;}"
    "input[type=text]:focus{border-color:#4f8cff;}"
    ".add-btn{background:#4f8cff;color:#fff;border:none;padding:10px 20px;"
    "border-radius:8px;font-size:14px;font-weight:600;cursor:pointer;margin-left:8px;}"
    ".search-wrap{position:relative;}"
    ".sugg{position:absolute;left:0;right:0;background:#1a2540;border:1px solid #4f8cff55;"
    "border-radius:10px;margin-top:4px;display:none;z-index:999;box-shadow:0 8px 24px #00000088;}"
    ".sugg-item{padding:11px 14px;cursor:pointer;font-size:14px;border-bottom:1px solid #1c2a4a;}"
    ".sugg-item:last-child{border-bottom:none;}"
    ".sugg-item:hover{background:#243049;}"
    ".sugg-item .ticker{font-weight:700;color:#4f8cff;margin-right:8px;}"
    ".sugg-item .already{font-size:11px;color:#4caf7d;margin-left:8px;}"
    ".rebuild-btn{background:#1c2a4a;color:#93a1bd;border:1px solid #243049;"
    "padding:9px 18px;border-radius:8px;font-size:13px;cursor:pointer;}"
    ".rebuild-btn:hover{background:#243049;color:#e7ecf6;}"
    "</style></head><body>"
    "<div style='max-width:640px;margin:40px auto;padding:0 16px;'>"
    "<div style='display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:24px;'>"
    "<div><h1>Manage Stocks</h1>"
    "<div class='sub'>NSE Catalyst Scanner &middot; <a href='/'>View dashboard</a></div></div>"
    "<form action='/rebuild' method='get'>"
    "<button class='rebuild-btn' type='submit'>&#8635; Rebuild now</button></form></div>"
    "ALERT_PH"
    "<div class='card'>"
    "<div style='font-size:14px;font-weight:600;margin-bottom:14px;'>Your watchlist (COUNT_PH stocks)</div>"
    "<table>ROWS_PH</table></div>"
    "<div class='card'>"
    "<div style='font-size:14px;font-weight:600;margin-bottom:12px;'>Add a stock</div>"
    "<div style='color:#93a1bd;font-size:12px;margin-bottom:10px;'>"
    "Type company name or NSE ticker &mdash; suggestions appear automatically</div>"
    "<form method='post' action='/add' id='add-form'>"
    "<div class='search-wrap'>"
    "<input type='text' id='search-input' placeholder='e.g. Wipro or TCS' autocomplete='off' style='width:calc(100% - 110px);'>"
    "<input type='hidden' name='ticker' id='selected-ticker'>"
    "<input type='hidden' name='name' id='selected-name'>"
    "<button class='add-btn' type='submit' id='add-btn' disabled>Add</button>"
    "<div class='sugg' id='suggestions'></div>"
    "</div></form>"
    "<div id='search-status' style='color:#93a1bd;font-size:12px;margin-top:8px;'></div>"
    "</div></div>"
    "<script>"
    "var timer=null;"
    "var inp=document.getElementById('search-input');"
    "var sugg=document.getElementById('suggestions');"
    "var hidden=document.getElementById('selected-ticker');"
    "var hiddenNm=document.getElementById('selected-name');"
    "var addBtn=document.getElementById('add-btn');"
    "var status=document.getElementById('search-status');"
    "inp.addEventListener('input',function(){"
    "  clearTimeout(timer);"
    "  hidden.value='';"
    "  addBtn.disabled=true;"
    "  var q=inp.value.trim();"
    "  if(q.length<2){sugg.style.display='none';status.textContent='';return;}"
    "  status.textContent='Searching...';"
    "  timer=setTimeout(function(){"
    "    fetch('/search?q='+encodeURIComponent(q))"
    "    .then(function(r){if(!r.ok)throw new Error('HTTP '+r.status);return r.json();})"
    "    .then(function(data){"
    "      sugg.innerHTML='';"
    "      if(!data.length){"
    "        sugg.style.display='none';"
    "        var raw=inp.value.trim().toUpperCase().replace(/[^A-Z0-9&-]/g,'');"
    "        if(raw.length>=2){"
    "          hidden.value=raw;hiddenNm.value='';"
    "          addBtn.disabled=false;"
    "          status.textContent='Not in list - will try \"'+raw+'\" directly. Click Add.';"
    "        }else{status.textContent='No NSE stocks found.';}"
    "        return;"
    "      }"
    "      data.forEach(function(item){"
    "        var d=document.createElement('div');"
    "        d.className='sugg-item';"
    "        d.innerHTML='<span class=\"ticker\">'+item.ticker+'</span>'+item.name+"
    "          (item.added?'<span class=\"already\">already added</span>':'');"
    "        d.addEventListener('mousedown',function(e){e.preventDefault();});"
    "        d.addEventListener('click',function(){"
    "          inp.value=item.ticker+'  —  '+item.name;"
    "          hidden.value=item.ticker;"
    "          hiddenNm.value=item.name;"
    "          sugg.style.display='none';"
    "          addBtn.disabled=item.added;"
    "          status.textContent=item.added?item.ticker+' already in watchlist.':'';"
    "        });"
    "        sugg.appendChild(d);"
    "      });"
    "      sugg.style.display='block';"
    "      status.textContent='';"
    "    })"
    "    .catch(function(err){sugg.style.display='none';status.textContent='Error: '+err.message;});"
    "  },380);"
    "});"
    "inp.addEventListener('blur',function(){setTimeout(function(){sugg.style.display='none';},200);});"
    "inp.addEventListener('focus',function(){if(sugg.innerHTML)sugg.style.display='block';});"
    "</script></body></html>"
)

@app.route("/manage")
def manage():
    core.reload_stocks()
    ok    = request.args.get("ok", "")
    error = request.args.get("error", "")

    stock_rows = ""
    for tic, val in core.STOCKS.items():
        name = val[0] if isinstance(val, (list, tuple)) else val.get("name", tic)
        stock_rows += (
            "<tr>"
            "<td style='padding:10px 14px;font-weight:600;'>" + tic + "</td>"
            "<td style='padding:10px 14px;color:#93a1bd;'>" + name + "</td>"
            "<td style='padding:10px 14px;'>"
            "<form method='post' action='/remove' style='margin:0'>"
            "<input type='hidden' name='ticker' value='" + tic + "'>"
            "<button type='submit' style='background:#1e0a0a;color:#e05c5c;"
            "border:1px solid #e05c5c44;padding:4px 12px;border-radius:8px;"
            "cursor:pointer;font-size:13px;'>Remove</button>"
            "</form></td></tr>"
        )

    alert = ""
    if ok:
        alert = ("<div style='background:#0d2a1a;border:1px solid #4caf7d44;color:#4caf7d;"
                 "padding:10px 16px;border-radius:8px;margin-bottom:16px;'>"
                 + ok.replace("+", " ") + "</div>")
    if error:
        alert = ("<div style='background:#2a0d0d;border:1px solid #e05c5c44;color:#e05c5c;"
                 "padding:10px 16px;border-radius:8px;margin-bottom:16px;'>"
                 + error.replace("+", " ") + "</div>")

    return _MANAGE_HTML.replace("ALERT_PH", alert).replace("COUNT_PH", str(len(core.STOCKS))).replace("ROWS_PH", stock_rows)


# ─────────────────────────────────────────────────────────────────────────────
# REST API  (consumed by Flutter mobile app)
# All endpoints return JSON.  Add  ?key=<API_KEY>  for future auth gating.
# ─────────────────────────────────────────────────────────────────────────────

def _cors(response):
    """Allow the Flutter app (any origin) to call these endpoints."""
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
    return response


@app.route("/api/stocks")
def api_stocks():
    """GET /api/stocks — summary card for every stock in the watchlist."""
    core.reload_stocks()
    import json as _json, os
    index_path = os.path.join(SCANNER_DIR, "site", "index.html")
    # Extract the embedded JSON data blob from the generated dashboard
    stocks_out = []
    try:
        with open(index_path, "r", encoding="utf-8") as f:
            html = f.read()
        marker = "const DATA = "
        start = html.find(marker)
        if start != -1:
            start += len(marker)
            end = html.find(";\n", start)
            data = _json.loads(html[start:end])
            stocks_out = data.get("stocks", [])
    except Exception:
        pass

    # Fallback: return basic info from config if index.html not available
    if not stocks_out:
        for tic, val in core.STOCKS.items():
            name = val[0] if isinstance(val, (list, tuple)) else val.get("name", tic)
            stocks_out.append({"ticker": tic, "name": name})

    return _cors(jsonify({"stocks": stocks_out, "count": len(stocks_out)}))


@app.route("/api/events")
def api_events():
    """GET /api/events — all flagged catalyst events, newest first.
    Optional: ?ticker=BAJFINANCE to filter by stock."""
    import json as _json, os
    ticker_filter = request.args.get("ticker", "").upper()
    events_out = []
    try:
        index_path = os.path.join(SCANNER_DIR, "site", "index.html")
        with open(index_path, "r", encoding="utf-8") as f:
            html = f.read()
        marker = "const DATA = "
        start = html.find(marker)
        if start != -1:
            start += len(marker)
            end = html.find(";\n", start)
            data = _json.loads(html[start:end])
            events_out = data.get("events", [])
    except Exception:
        pass

    if ticker_filter:
        events_out = [e for e in events_out if e.get("ticker") == ticker_filter]

    return _cors(jsonify({"events": events_out, "count": len(events_out)}))


@app.route("/api/stock/<ticker>")
def api_stock_detail(ticker):
    """GET /api/stock/<TICKER> — full detail for one stock (chart data + events + intel)."""
    import json as _json, os
    ticker = ticker.upper()
    try:
        index_path = os.path.join(SCANNER_DIR, "site", "index.html")
        with open(index_path, "r", encoding="utf-8") as f:
            html = f.read()
        marker = "const DATA = "
        start = html.find(marker)
        if start != -1:
            start += len(marker)
            end = html.find(";\n", start)
            data = _json.loads(html[start:end])
            stock = next((s for s in data.get("stocks", []) if s["ticker"] == ticker), None)
            events = [e for e in data.get("events", []) if e.get("ticker") == ticker]
            if stock:
                stock["events"] = events
                return _cors(jsonify(stock))
    except Exception as e:
        return _cors(jsonify({"error": str(e)})), 500
    return _cors(jsonify({"error": f"{ticker} not found in watchlist"})), 404


@app.route("/api/search")
def api_search():
    """GET /api/search?q=<query> — stock suggestions from static NSE list."""
    q = request.args.get("q", "").strip().lower()
    if len(q) < 1:
        return _cors(jsonify([]))
    current = set(core.STOCKS.keys())
    results = []
    for ticker, name in _NSE_STOCKS:
        if q in ticker.lower() or q in name.lower():
            results.append({
                "ticker": ticker,
                "name": name,
                "added": ticker in current
            })
        if len(results) >= 10:
            break
    return _cors(jsonify(results))


@app.route("/api/watchlist", methods=["GET"])
def api_watchlist():
    """GET /api/watchlist — just the list of tickers + names currently tracked."""
    core.reload_stocks()
    out = []
    for tic, val in core.STOCKS.items():
        name = val[0] if isinstance(val, (list, tuple)) else val.get("name", tic)
        out.append({"ticker": tic, "name": name})
    return _cors(jsonify(out))


@app.route("/api/health")
def api_health():
    """GET /api/health — simple liveness check for the mobile app."""
    import datetime
    return _cors(jsonify({"status": "ok", "timestamp": datetime.datetime.utcnow().isoformat()}))
