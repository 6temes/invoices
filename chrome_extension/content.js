// The popup is built from DOM nodes, never markup, because the issue title and
// client names are text from other people.
function element(tag, properties = {}, children = []) {
  const node = Object.assign(document.createElement(tag), properties)
  node.append(...children)
  return node
}

;(async () => {
  const settings = await chrome.storage.local.get(['apiUrl', 'apiToken'])
  if (!settings.apiUrl || !settings.apiToken) return

  // Parse current page
  const pathParts = window.location.pathname.split('/')
  const repoSlug = `${pathParts[1]}/${pathParts[2]}`
  const issueNumber = pathParts[4]
  const titleEl = document.querySelector('.js-issue-title, [data-testid="issue-title"]')
  const title = titleEl ? titleEl.textContent.trim() : ''

  // Fetch clients and match repo
  let clients = []
  let matchedClient = null
  try {
    const res = await fetch(`${settings.apiUrl}/api/clients`, {
      headers: { 'Authorization': `Bearer ${settings.apiToken}` }
    })
    clients = await res.json()
    matchedClient = clients.find(c =>
      c.github_repos && c.github_repos.some(r => r === repoSlug)
    )
  } catch (e) {
    console.error('Invoice extension: failed to fetch clients', e)
  }

  // Create button
  const btn = document.createElement('button')
  btn.textContent = 'Log hours'
  btn.className = 'inv-log-btn'
  btn.addEventListener('click', () => showPopup())

  // Insert near the title
  const headerActions = document.querySelector('.gh-header-actions')
  if (headerActions) {
    headerActions.prepend(btn)
  } else {
    const header = document.querySelector('.js-issue-title, [data-testid="issue-title"]')
    if (header) header.parentElement.appendChild(btn)
  }

  function showPopup() {
    // Remove existing popup
    document.querySelector('.inv-popup')?.remove()

    const close = element('button', { className: 'inv-popup-close', textContent: '×' })
    const save = element('button', { className: 'inv-save-btn', textContent: 'Save' })
    const options = clients.map(c =>
      element('option', { value: String(c.id), textContent: c.name, selected: matchedClient?.id === c.id })
    )

    const popup = element('div', { className: 'inv-popup' }, [
      element('div', { className: 'inv-popup-header' }, [
        element('strong', { textContent: 'Log Hours' }),
        close
      ]),
      element('div', { className: 'inv-popup-body' }, [
        element('label', { textContent: 'Client' }),
        element('select', { className: 'inv-select' }, options),
        element('label', { textContent: 'Hours' }),
        element('input', { type: 'number', step: '0.25', min: '0.25', value: '1', className: 'inv-hours' }),
        element('label', { textContent: 'Description' }),
        element('input', { type: 'text', value: `#${issueNumber} — ${title}`, className: 'inv-desc' }),
        save,
        element('div', { className: 'inv-status' })
      ])
    ])

    document.body.appendChild(popup)

    close.addEventListener('click', () => popup.remove())
    save.addEventListener('click', () => saveHours(popup))
  }

  async function saveHours(popup) {
    const statusEl = popup.querySelector('.inv-status')
    const saveBtn = popup.querySelector('.inv-save-btn')

    const data = {
      client_id: parseInt(popup.querySelector('.inv-select').value),
      hours: parseFloat(popup.querySelector('.inv-hours').value),
      description: popup.querySelector('.inv-desc').value,
      performed_on: new Date().toISOString().split('T')[0],
      github_url: window.location.href
    }

    saveBtn.disabled = true
    statusEl.textContent = 'Saving...'

    try {
      const res = await fetch(`${settings.apiUrl}/api/extra_hours`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${settings.apiToken}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(data)
      })

      if (res.ok) {
        statusEl.textContent = 'Saved!'
        statusEl.style.color = '#059669'
        btn.textContent = 'Logged!'
        btn.style.background = '#d1fae5'
        setTimeout(() => popup.remove(), 1500)
      } else {
        const err = await res.json()
        statusEl.textContent = err.errors ? err.errors.join(', ') : 'Failed to save'
        statusEl.style.color = '#dc2626'
        saveBtn.disabled = false
      }
    } catch (e) {
      statusEl.textContent = 'Network error'
      statusEl.style.color = '#dc2626'
      saveBtn.disabled = false
    }
  }
})()
