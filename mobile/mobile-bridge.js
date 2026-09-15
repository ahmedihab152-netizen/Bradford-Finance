import { Capacitor } from '@capacitor/core';
import { App } from '@capacitor/app';
import { Share } from '@capacitor/share';
import { StatusBar, Style } from '@capacitor/status-bar';

const isNative = Capacitor.isNativePlatform();
const publicUrl = 'https://app.bradforderp.com';

function showConnectivity() {
  let banner = document.querySelector('#mobileConnectivity');
  if (!banner) {
    banner = document.createElement('div');
    banner.id = 'mobileConnectivity';
    banner.className = 'mobile-connectivity hidden';
    banner.textContent = 'لا يوجد اتصال بالإنترنت — لن يتم حفظ أي حركة حتى عودة الاتصال.';
    document.body.append(banner);
  }
  banner.classList.toggle('hidden', navigator.onLine);
}

function addMobileActions() {
  const actions = document.querySelector('.top .actions');
  if (!actions || actions.querySelector('#nativeShareBtn')) return;
  const button = document.createElement('button');
  button.id = 'nativeShareBtn';
  button.className = 'btn ghost mobile-share';
  button.type = 'button';
  button.textContent = 'مشاركة';
  button.addEventListener('click', async () => {
    try {
      await Share.share({ title: 'Bradford ERP', text: 'نظام Bradford ERP', url: publicUrl, dialogTitle: 'مشاركة Bradford ERP' });
    } catch (error) {
      if (!String(error?.message || error).toLowerCase().includes('cancel')) console.warn(error);
    }
  });
  actions.prepend(button);
}

function addLegalLinks() {
  const box = document.querySelector('.auth-side .box');
  if (!box || box.querySelector('.mobile-legal')) return;
  const links = document.createElement('nav');
  links.className = 'mobile-legal';
  links.setAttribute('aria-label', 'الدعم والخصوصية');
  links.innerHTML = '<a href="support.html">الدعم</a><a href="privacy.html">الخصوصية</a><a href="account-deletion.html">حذف الحساب</a>';
  box.append(links);
}

window.addEventListener('online', showConnectivity);
window.addEventListener('offline', showConnectivity);
document.addEventListener('DOMContentLoaded', () => {
  document.documentElement.classList.toggle('native-app', isNative);
  showConnectivity();
  addMobileActions();
  addLegalLinks();
  new MutationObserver(() => {
    addMobileActions();
    addLegalLinks();
  }).observe(document.body, { subtree: true, childList: true });
});

if (isNative) {
  StatusBar.setStyle({ style: Style.Dark }).catch(console.warn);
  StatusBar.setBackgroundColor({ color: '#ffffff' }).catch(console.warn);

  App.addListener('backButton', ({ canGoBack }) => {
    const modal = document.querySelector('#modal:not(.hidden)');
    if (modal && typeof window.closeM === 'function') return window.closeM();
    if (canGoBack) return history.back();
    App.minimizeApp();
  });

  App.addListener('appUrlOpen', ({ url }) => {
    try {
      const target = new URL(url);
      if (target.hostname === 'app.bradforderp.com') location.assign(`${target.pathname}${target.search}${target.hash}`);
    } catch (error) {
      console.warn('Ignored invalid app URL', error);
    }
  });
}
