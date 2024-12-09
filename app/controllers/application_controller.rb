class ApplicationController < ActionController::API
  include FacetRailsCommon::ApplicationControllerMethods
  before_action :set_api_version, :enforce_stop_block

  def set_api_version
    ApiResponseContext.api_version = params.fetch(:api_version, '1')
  end
  
  def enforce_stop_block
    return if ENV["STOP_BLOCK_NUMBER"].blank?
    
    core_indexer_status = Rails.cache.fetch("core_indexer_status", expires_in: 12.seconds) do
      EthsIndexerClient.indexer_status
    end
    
    current_block_number = core_indexer_status["current_block_number"]
    
    if current_block_number.present? && current_block_number > ENV["STOP_BLOCK_NUMBER"].to_i
      render json: { error: "Facet V1 is shutting down and migrating to Facet V2! For more information, see https://docs.facet.org" }, status: 422
    end
  end
  
  def cursor_mode?
    !!(
      ApiResponseContext.api_version.to_i >= 2 ||
      params[:user_cursor_pagination] ||
      params[:use_cursor_pagination] ||
      params[:page_key]
    )
  end
  
  def page_mode?
    !cursor_mode?
  end
  
  def v1_page_params
    page = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 50).to_i
    per_page = 50 if per_page > 50
    
    [page, per_page]
  end
end
