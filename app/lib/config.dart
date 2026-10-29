/// Endpoints and product constants. The daily data lives on a static CDN
/// (GitHub Pages) so the app never waits for a server cold start; the Render
/// API is only used for feedback and on-demand analysis.
const kDataUrl = 'https://angelgarg.github.io/nse-catalyst-scanner/data/v1';
const kApiUrl = 'https://nse-catalyst-scanner.onrender.com';
const kSiteUrl = 'https://angelgarg.github.io/nse-catalyst-scanner';
const kPrivacyUrl = '$kSiteUrl/privacy.html';
const kTermsUrl = '$kSiteUrl/terms.html';
const kPlayUrl = 'https://play.google.com/store/apps/details?id=com.angelgarg.spikewise';

const kProMonthly = 'spikewise_pro_monthly';
const kProYearly = 'spikewise_pro_yearly';
const kProductIds = {kProMonthly, kProYearly};

const kDefaultWatchlist = ['RELIANCE', 'HDFCBANK', 'INFY', 'TCS', 'ICICIBANK'];

/// File name used for a ticker in the data build ('M&M' -> 'M_M').
String fileKey(String ticker) => ticker.replaceAll('&', '_');
