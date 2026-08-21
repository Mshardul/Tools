/**
 * MV3 service worker: context menu + action → Native Messaging host.
 * Host name must match com.tools.send_to_downloader.json "name".
 */
const NATIVE_HOST = "com.tools.send_to_downloader";
const MENU_ID = "send-to-tools-downloader";

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({
      id: MENU_ID,
      title: "Send to Tools downloader",
      contexts: ["page", "link", "video", "audio"],
    });
  });
});

/**
 * @param {{ url: string, title?: string }} payload
 * @returns {Promise<{ ok: boolean, error?: string, entry?: object }>}
 */
function sendToNative(payload) {
  return new Promise((resolve) => {
    let port;
    try {
      port = chrome.runtime.connectNative(NATIVE_HOST);
    } catch (err) {
      resolve({ ok: false, error: String(err) });
      return;
    }

    let settled = false;
    const finish = (result) => {
      if (settled) return;
      settled = true;
      try {
        port.disconnect();
      } catch (_) {
        /* ignore */
      }
      resolve(result);
    };

    port.onMessage.addListener((msg) => {
      finish(msg && typeof msg === "object" ? msg : { ok: false, error: "bad host reply" });
    });
    port.onDisconnect.addListener(() => {
      const err = chrome.runtime.lastError;
      finish({
        ok: false,
        error: err ? err.message : "native host disconnected",
      });
    });

    port.postMessage({
      action: "add",
      url: payload.url,
      title: payload.title || "",
    });
  });
}

/**
 * @param {number|undefined} tabId
 */
async function queueActiveTab(tabId) {
  let tab;
  if (tabId != null) {
    tab = await chrome.tabs.get(tabId);
  } else {
    const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
    tab = tabs[0];
  }
  if (!tab || !tab.url) {
    return { ok: false, error: "no active tab URL" };
  }
  const url = tab.url;
  if (!/^https?:\/\//i.test(url)) {
    return { ok: false, error: "only http(s) pages can be queued" };
  }
  return sendToNative({ url, title: tab.title || "" });
}

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  if (info.menuItemId !== MENU_ID) return;
  const url = info.linkUrl || info.srcUrl || (tab && tab.url) || "";
  const title = (tab && tab.title) || "";
  const result = await sendToNative({ url, title });
  if (!result.ok) {
    console.error("send-to-downloader:", result.error || result);
  }
});

chrome.action.onClicked.addListener(async (tab) => {
  // With default_popup set, onClicked usually does not fire; popup calls queue instead.
  const result = await queueActiveTab(tab && tab.id);
  if (!result.ok) {
    console.error("send-to-downloader:", result.error || result);
  }
});

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (!message || message.type !== "queue-active-tab") {
    return false;
  }
  queueActiveTab()
    .then((result) => sendResponse(result))
    .catch((err) => sendResponse({ ok: false, error: String(err) }));
  return true;
});
