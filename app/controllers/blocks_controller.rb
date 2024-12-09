class BlocksController < ApplicationController
  cache_actions_on_block
  before_action :set_eth_block_scope

  def index
    if page_mode?
      page, per_page = v1_page_params
      
      scope = @eth_block_scope.order(block_number: :desc)

      etag = EthBlock.max_processed_block_number
      
      set_cache_control_headers(etag: etag, max_age: 12.seconds) do
        cache_key = ["blocks_index", scope, page, per_page, etag]
        
        result = Rails.cache.fetch(cache_key) do
          res = scope.page(page).per(per_page).to_a
          numbers_to_strings(res)
        end

        render json: {
          result: result
        }
      end
    else
      render_paginated_json(@eth_block_scope)
    end
  end

  def show
    eth_block = @eth_block_scope.find_by(block_number: params[:id])

    raise RequestedRecordNotFound unless eth_block

    render json: { result: numbers_to_strings(eth_block) }
  end

  def total
    total_blocks = @eth_block_scope.count
    
    render json: { result: numbers_to_strings(total_blocks) }
  end
  
  private
  
  def set_eth_block_scope
    @eth_block_scope = if system_start_block.present?
                         EthBlock.processed.where("block_number >= ?", system_start_block)
                       else
                         EthBlock.none
                       end
  end

  def system_start_block
    @_system_start_block ||= SystemConfigVersion.current.start_block_number
  end
end
