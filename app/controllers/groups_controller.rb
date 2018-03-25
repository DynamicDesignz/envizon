# @restful_api 1.0
# Handle all things group related
class GroupsController < ApplicationController
  # @url /groups/new
  # @action GET
  #
  # renders :new, a form for group creation
  def new
    respond_to do |format|
      format.html { redirect_to root_path }
      format.js { render :new }
    end
  end

  # @url /groups
  # @action POST
  #
  # Creates a new group
  #
  # @required [String] :group[:name] Name of the new group
  # @optional [Integer] :source_group ID of the source group
  # @optional [Array<Integer>] :selected_clients IDs of selected clients
  # @optional [String] :search true/false, indicator if :selected_clients are a result of a search
  # @optional [String] :move true/false, indicator if :selected_clients should be moved to the new group
  def create
    name = params[:group][:name]
    selected_clients = params[:selected_clients] if params[:selected_clients].present?
    search = ActiveModel::Type::Boolean.new.cast params[:search]
    source_group = search || params[:source_group].blank? ? nil : Group.find(params[:source_group])
    destination_group = Group.new
    destination_group.name = name.blank? ? 'Unknown' : name
    destination_group.icon = '<i class="fa ' + params[:group][:icon] + '"></i>'
    destination_group.mod = true

    render(:create_custom) && return unless destination_group.save # warn instead?

    respond_with_refresh('New empty group created') && return unless selected_clients.present?

    if params[:move].present? && params[:move].casecmp('true').zero?
      move_do(selected_clients, destination_group, source_group, search)
    else
      selected_clients.each { |selected| destination_group.clients << Client.find(selected) }
    end

    destination_group.save

    message = "New group '#{destination_group.name}' with #{selected_clients.length} clients saved."
    respond_with_refresh(message)
  end

  # @url /groups/create_form
  # @action POST
  #
  # Renders a form for group creation, providing clients
  def create_form
    prepare_form(:create_custom)
  end

  # @url /groups/move_form
  # @action POST
  #
  # Renders a form for moving clients
  def move_form
    prepare_form(:move)
  end

  # @url /groups/move
  # @action POST
  #
  # Moves clients to a group
  #
  # @required [String] :destination_group target group ID
  # @required [Integer] :source_group ID of the source group
  # @required [Array<Integer>] :selected_clients IDs of selected clients
  # @optional [String] :search true/false, indicator if :selected_clients are a result of a search
  def move
    destination_group = Group.find(params[:destination_group])
    source_group = Group.find(params[:source_group]) unless params[:source_group] == '-1'
    search = ActiveModel::Type::Boolean.new.cast params[:search]

    move_do(params[:selected_clients], destination_group, source_group, search)

    message = "Moved #{params[:selected_clients].length} clients to group '#{destination_group.name}'"
    respond_with_refresh(message)
  end

  # @url /groups/copy_form
  # @action POST
  #
  # Renders a form for moving clients
  def copy_form
    prepare_form(:copy)
  end

  # @url /groups/copy
  # @action POST
  #
  # Copies clients to a group
  #
  # @required [String] :destination_group target group ID
  # @required [Array<Integer>] :selected_clients IDs of selected clients
  def copy
    destination_group = Group.find(params[:destination_group])

    params[:selected_clients].each { |selected| destination_group.clients << Client.find(selected) }

    message = "Copied #{params[:selected_clients].length} clients to group '#{destination_group.name}'"
    respond_with_refresh(message)
  end

  # @url /groups/delete_clients_form
  # @action POST
  #
  # Renders a form for deleting clients
  def delete_clients_form
    prepare_form(:delete_clients)
  end

  # Renders a form for deleting clients
  def delete_form
    source_group ||= Group.find(params[:source_group]) unless params[:source_group].blank?
    clients = Client.find(params[:clients]) if params.key?(:clients)
    if (clients.blank? && source_group.clients.present?) || source_group.nil?
      respond_with_notify
    else
      clients ||= []
      locals = { source_group: source_group, clients: clients }
      respond_root_path_js(:delete_group, locals)
    end
  end

  # @url /groups/delete
  # @action POST
  #
  # Delete a group
  #
  # @required [String] :source_group ID of group to delete
  def delete
    source_group = Group.find(params[:source_group])

    source_group.clients.each { |client| client.destroy if client.groups.length == 1 }

    message = "Deleted Group '#{source_group.name}'"
    deleted = source_group.id
    source_group.destroy

    respond_to do |format|
      format.html {}
      format.js { render 'pages/group_refresh', locals: { message: message, close: true, delete: deleted, type: 'notice' } }
    end
  end

  # @url /groups/delete_clients
  # @action POST
  #
  # Deletes clients from a group (and the client itself if doesn't remain in any group or it was a search result)
  #
  # @required [String] :source_group ID of group to delete
  # @required [Array<Integer>] :selected_clients IDs of selected clients
  # @optional [String] :search true/false, indicator if :selected_clients are a result of a search
  def delete_clients
    search = ActiveModel::Type::Boolean.new.cast params[:search]
    source_group = Group.find(params[:source_group]) unless search
    selected_clients = params[:selected_clients]

    if search
      selected_clients.each do |selected|
        client = Client.find(selected)
        client.groups.each { |group| group.clients.delete(client) }
        client.destroy
      end
      message = "Deleted #{selected_clients.length} clients."
    else
      selected_clients.each do |selected|
        client = Client.find(selected)
        source_group.clients.delete(client)
        client.destroy if client.groups.empty?
      end
      message = "Deleted #{selected_clients.length} clients from group '#{source_group.name}'"
    end

    respond_with_refresh(message)
  end

  def scan_form
    clients = Client.find(params[:clients]) if params.key?(:clients)
    if clients.blank?
      respond_with_notify
    else
      locals = { clients: clients }
      respond_root_path_js(:scan, locals)
    end
  end

  # @url /groups/export_form
  # @action POST
  #
  # Renders a form to export clients
  def export_form
    clients = Client.find(params[:clients]) if params.key?(:clients)

    if clients.nil? || clients.empty?
      respond_with_notify
    else
      locals = { clients: clients }
      respond_root_path_js(:export, locals)
    end
  end

  # @url /groups/export
  # @action POST
  #
  # Exports selected clients' IPs as a .yml - file
  #
  # @required [String] :group[:file_name] desired file_name
  # @required [Array<Integer>] :selected_clients IDs of selected clients
  def export
    file_name = (params[:group][:file_name].present? ? params[:group][:file_name] : 'exported_clients')
    clients = Client.where(id: params[:selected_clients]) if params[:selected_clients].present?
    if file_name && clients.present?
      file_name << '.txt' unless file_name =~ /.+\.(yml|yaml|txt)$/
      if file_name =~ /.+\.(yml|yaml)$/
        exceptions = %w[id created_at updated_at icon client_id]
        data = clients.left_outer_joins(:outputs, :ports).distinct.map do |c|
          ary = [c.attributes.except(*exceptions)]
          ary  << { 'ports' => c.ports.map { |p| p.attributes.except(*exceptions) } }
          ary  << { 'outputs' => c.outputs.map { |o| o.attributes.except(*exceptions) } }
        end
        send_data YAML.dump(data), filename: file_name, type: 'application/yaml'
      else
        data = clients.map(&:ip).join("\n")
        send_data data, filename: file_name, type: 'text/plain'
      end
    else
      respond_with_notify('That didn\'t work.', 'alert')
    end
  end

  private

  def respond_with_refresh(message, type = 'notice')
    respond_to do |format|
      format.html { redirect_to root_path }
      format.js { render 'pages/group_refresh', locals: { message: message, close: true, type: type } }
    end
  end

  def respond_with_notify(message = 'Please make a selection', type = 'alert')
    respond_to do |format|
      format.html { redirect_to root_path }
      format.js { render 'pages/notify', locals: { message: message, type: type } }
    end
  end

  def respond_root_path_js(sym, locals)
    respond_to do |format|
      format.html { redirect_to root_path }
      format.js { render sym, locals: locals }
    end
  end

  def prepare_form(sym)
    search = ActiveModel::Type::Boolean.new.cast params[:search]
    if search
      Struct.new('FakeGroup', :name, :id)
      source_group = Struct::FakeGroup.new('Custom search result', -1)
    end

    if params.key?(:clients)
      clients = Client.find(params[:clients])
      source_group ||= Group.find(params[:source_group]) unless params[:source_group].nil?
    end
    if clients.blank? || source_group.blank?
      respond_with_notify
    else
      locals = { source_group: source_group, clients: clients, search: search }
      respond_root_path_js(sym, locals)
    end
  end

  def move_do(selected_clients, destination_group, source_group, search)
    selected_clients.each do |selected|
      client = Client.find(selected)
      destination_group.clients << client
      next unless destination_group.save
      if search
        client.groups.each { |group| group.clients.delete client unless group == destination_group }
      else
        source_group.clients.delete client
      end
    end
  end
end