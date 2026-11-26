require "test_helper"

class ActiveStorageAuthenticationTest < ActionDispatch::IntegrationTest
  setup do
    @invoice = invoices(:acme_january)
    attach_deliverables @invoice
  end

  test "direct uploads require a session" do
    assert_no_difference -> { ActiveStorage::Blob.count } do
      post rails_direct_uploads_path, params: { blob: { filename: "upload.pdf", byte_size: 8, checksum: Digest::MD5.base64digest("%PDF-1.4"), content_type: "application/pdf" } }, as: :json
    end

    assert_redirected_to new_session_path
  end

  test "disk service uploads require a session" do
    blob = ActiveStorage::Blob.create_before_direct_upload!(filename: "upload.pdf", byte_size: 8, checksum: Digest::MD5.base64digest("%PDF-1.4"), content_type: "application/pdf")
    url = ActiveStorage::Current.set(url_options: { host: "www.example.com" }) { blob.service_url_for_direct_upload }

    put url, params: "%PDF-1.4", headers: blob.service_headers_for_direct_upload

    assert_redirected_to new_session_path
    assert_not blob.service.exist?(blob.key)
  end

  test "blob downloads require a session" do
    get rails_blob_path(@invoice.pdf, disposition: "attachment")

    assert_redirected_to new_session_path
  end

  test "disk service urls require a session" do
    url = ActiveStorage::Current.set(url_options: { host: "www.example.com" }) { @invoice.pdf.url }

    get url

    assert_redirected_to new_session_path
  end

  test "the signed-in owner downloads an invoice pdf" do
    sign_in_as users(:daniel)

    get rails_blob_path(@invoice.pdf, disposition: "attachment")
    follow_redirect!

    assert_response :success
    assert_equal "%PDF-1.4", response.body
  end
end
