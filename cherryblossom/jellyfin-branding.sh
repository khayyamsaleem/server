#!/bin/bash
# Jellyfin branding init — injects ElegantFin theme + JUUL branding into branding.xml
# and replaces favicon/logo with custom JUUL assets.
# Runs before Jellyfin starts to ensure theme is always applied.

BRANDING_FILE="/config/config/branding.xml"
CACHE_BUST=$(date +%s)

# JUUL-styled login disclaimer (HTML supported in LoginDisclaimer)
LOGIN_DISCLAIMER='<div style="text-align:center;margin-top:1em;font-family:monospace;">
<pre style="display:inline-block;text-align:left;color:#0087ff;font-size:0.55em;line-height:1.2;letter-spacing:0.05em;">
    ██╗██╗   ██╗██╗   ██╗██╗
    ██║██║   ██║██║   ██║██║
    ██║██║   ██║██║   ██║██║
██  ██║██║   ██║██║   ██║██║
╚████╔╝╚██████╔╝╚██████╔╝██████╗
 ╚═══╝  ╚═════╝  ╚═════╝ ╚═════╝
</pre>
</div>
<script>
(function(){var h="/web/juul-favicon.svg?v="+Date.now();var l=document.querySelector("link[rel*=\"icon\"]");if(l){l.type="image/svg+xml";l.href=h;}else{l=document.createElement("link");l.rel="icon";l.type="image/svg+xml";l.href=h;document.head.appendChild(l);}})();
</script>'

# ElegantFin theme + JUUL accent color overrides + logo replacement CSS
CUSTOM_CSS="@import url(\"https://cdn.jsdelivr.net/gh/lscambo13/ElegantFin@main/Theme/ElegantFin-jellyfin-theme-build-latest-minified.css\");

/* JUUL branding overrides */
:root {
    --accent: 0, 135, 255 !important;
    --loginPageBgUrl: none;
}

/* Replace top-left Jellyfin logo with JUUL text + device underline */
.pageTitleWithDefaultLogo {
    background-image: url(/web/juul-logo.svg?v=${CACHE_BUST}) !important;
    background-size: contain;
    background-repeat: no-repeat;
    background-position: left center;
    height: 40px !important;
    width: 130px !important;
}

/* login disclaimer styling */
.disclaimerContainer {
    opacity: 0.85;
}
"

echo "[jellyfin-branding] Injecting ElegantFin theme + JUUL branding..."

cat > "$BRANDING_FILE" << XMLEOF
<?xml version="1.0" encoding="utf-8"?>
<BrandingOptions xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
  <LoginDisclaimer><![CDATA[${LOGIN_DISCLAIMER}]]></LoginDisclaimer>
  <CustomCss><![CDATA[${CUSTOM_CSS}]]></CustomCss>
  <SplashscreenEnabled>true</SplashscreenEnabled>
</BrandingOptions>
XMLEOF

echo "[jellyfin-branding] Branding applied (cache bust: ${CACHE_BUST})."

# Hand off to the real Jellyfin entrypoint
exec /jellyfin/jellyfin "$@"
