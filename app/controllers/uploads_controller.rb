class UploadsController < ApplicationController
  before_action :member_only, except: [:index, :show]
  respond_to :html, :xml, :json, :js
  skip_before_action :verify_authenticity_token, only: [:preprocess]

  def new
    if CurrentUser.can_upload_with_reason == :REJ_UPLOAD_NEWBIE
      return access_denied("You can not upload during your first week.")
    end
    @source = Sources::Strategies.find(params[:url], params[:ref]) if params[:url].present?
    @upload_notice_wiki = WikiPage.titled(Danbooru.config.upload_notice_wiki_page).first
    @upload = Upload.new
    respond_with(@upload)
  end

  def batch
    @url = params.dig(:batch, :url) || params[:url]
    @source = Sources::Strategies.find(@url, params[:ref]) if @url.present?
    respond_with(@source)
  end

  def index
    @uploads = Upload.search(search_params).includes(:post, :uploader).paginate(params[:page], :limit => params[:limit])
    respond_with(@uploads) do |format|
      format.xml do
        render :xml => @uploads.to_xml(:root => "uploads")
      end
    end
  end

  def show
    @upload = Upload.find(params[:id])
    respond_with(@upload) do |format|
      format.html do
        if @upload.is_completed? && @upload.post_id
          redirect_to(post_path(@upload.post_id))
        end
      end
    end
  end

  def create
    @service = UploadService.new(upload_params)
    @upload = @service.start!

    if @upload.invalid?
      flash[:notice] = @upload.errors.full_messages.join("; ")
      return render json: {success: false, reason: 'invalid', message: @upload.errors.full_messages.join("; ")}, status: 412
    end
    if @service.warnings.any?
      flash[:notice] = @service.warnings.join(".\n \n")
    end

    respond_to do |format|
      format.json do
        return render json: {success: false, reason: 'duplicate', location: post_path(@upload.duplicate_post_id), post_id: @upload.duplicate_post_id}, status: 412 if @upload.is_duplicate?
        return render json: {success: false, reason: 'invalid', message: @upload.sanitized_status}, status: 412 if @upload.is_errored?

        render json: {success: true, location: post_path(@upload.post_id), post_id: @upload.post_id}
      end
    end
  end

  private

  def upload_params
    permitted_params = %i[
      file direct_url source tag_string rating parent_id description description referer_url md5_confirmation as_pending
    ]

    permitted_params << :locked_tags if CurrentUser.is_admin?
    permitted_params << :locked_rating if CurrentUser.is_privileged?

    params.require(:upload).permit(permitted_params)
  end
end
