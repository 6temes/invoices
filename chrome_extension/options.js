document.addEventListener('DOMContentLoaded', async () => {
  const settings = await chrome.storage.local.get(['apiUrl', 'apiToken'])
  document.getElementById('apiUrl').value = settings.apiUrl || ''
  document.getElementById('apiToken').value = settings.apiToken || ''
})

document.getElementById('save').addEventListener('click', async () => {
  const apiUrl = document.getElementById('apiUrl').value.replace(/\/$/, '')
  const apiToken = document.getElementById('apiToken').value

  const url = new URL(apiUrl)
  if (url.protocol !== 'https:') {
    document.getElementById('status').textContent = 'API URL must use HTTPS'
    return
  }

  await chrome.storage.local.set({ apiUrl, apiToken })
  document.getElementById('status').textContent = 'Settings saved!'
  setTimeout(() => {
    document.getElementById('status').textContent = ''
  }, 3000)
})
