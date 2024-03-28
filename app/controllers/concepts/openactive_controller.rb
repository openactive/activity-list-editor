# encoding: UTF-8

# Copyright 2011-2013 innoQ Deutschland GmbH
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'zip'

#Derived from hierarchy_controller.rb
class Concepts::OpenactiveController < ConceptsController

  def index
    authorize! :read, Iqvoc::Concept.base_class

    scope = Iqvoc::Concept.base_class
    scope = scope.published

    # only select unexpired concepts
    # TODO decide handling of expired concepts for OA list
    scope = scope.published.not_expired.includes(:broader_relations, :narrower_relations, :notes, :notations, :alt_labels, :pref_labels)

    @concepts = scope

    @collections = Iqvoc::Collection.base_class.published.includes(:members, :notes, :alt_labels, :pref_labels)

    # When in single query mode, AR handles ALL includes to be loaded by that
    # one query. We don't want that! So let's do it manually :-)
    #    ActiveRecord::Associations::Preloader.new.preload(@concepts,
    #        Iqvoc::Concept.base_class.default_includes + [])

    @concepts.to_a.sort_by! {|c| c.pref_label }
        
    respond_to do |format|
      format.zip do
        # Create in-memory zip file
        buffer = Zip::OutputStream.write_buffer do |zip|
          # Adding activity-list.jsonld to the ZIP
          concepts_json = generate_concepts_json(@concepts) # This method encapsulates the JSON generation logic
          zip.put_next_entry("#{ENV['VOCAB_IDENTIFIER']}.jsonld")
          zip.write(concepts_json)

          # Generate and add collections JSON files
          @collections.select { |c| can? :read, c }.each do |collection|
            collection_json = generate_collection_json(collection) # This method encapsulates the JSON generation logic
            zip.put_next_entry("collections/#{collection.origin[1..-1]}.jsonld")
            zip.write(collection_json)
          end
        end

        # Rewind the buffer to allow for reading
        buffer.rewind

        # Send the data to the client as a file download
        send_data(buffer.read, filename: "#{ENV['VOCAB_IDENTIFIER']}.zip", type: 'application/zip')
      end
    end
  end

  def confirm_export
    # This action will render a view asking for confirmation
  end

  def trigger_export
    if params[:confirm] == 'yes'
      client = Octokit::Client.new(:login => ENV['VOCAB_WORKFLOW_GH_UID'], :password => ENV['VOCAB_WORKFLOW_GH_ACCESS_TOKEN'])
      repo = "openactive/#{ENV['VOCAB_IDENTIFIER']}"
      workflow_id = 'create-and-merge-pr.yaml'
      ref = 'master'
      options = {
        'inputs' => {
          'publisher' => current_user.name,
        }
      }

      client.workflow_dispatch(repo, workflow_id, ref, options)
    else
      redirect_to confirm_export_path
    end
    
  end

  private

  # Define the methods to generate JSON for concepts and collections
  def generate_concepts_json(input_concepts)
    concepts = input_concepts.select { |c| can? :read, c }.map do |c|
      url = "https://openactive.io/#{ENV['VOCAB_IDENTIFIER']}##{c.origin[1..-1]}"
#      definition = c.notes_for_class(Note::SKOS::Definition).empty? ? "" : c.notes_for_class(Note::SKOS::Definition).first.value
      broader = []
      c.broader_relations.each do |rel|
        broader << "https://openactive.io/#{ENV['VOCAB_IDENTIFIER']}##{rel.target.origin[1..-1]}"
      end
      narrower = []
      c.narrower_relations.each do |rel|
        narrower << "https://openactive.io/#{ENV['VOCAB_IDENTIFIER']}##{rel.target.origin[1..-1]}"
      end
      klass = Iqvoc::Concept.further_relation_classes.first # XXX: arbitrary; bad heuristic?
      only_published = params[:published] != "0"
      related = []
      c.related_concepts_for_relation_class(klass, only_published).each do |related_concept|
        related << "https://openactive.io/#{ENV['VOCAB_IDENTIFIER']}##{related_concept.origin[1..-1]}"
      end
      concept = {
          id: url,
          identifier: c.origin[1..-1],
          type: "Concept",
          prefLabel: c.pref_label.to_s
      }
      concept[:broader] = broader if broader.any?
      concept[:narrower] = narrower if narrower.any?
      concept[:related] = related if related.any?
      c.notes_for_class(Note::SKOS::Definition).each do |n|
        concept[:definition] = n.value
      end
      c.notations.each do |n|
        concept[:notation] = n.value
      end

      concept[:topConceptOf] = "https://openactive.io/#{ENV['VOCAB_IDENTIFIER']}" if c.top_term?
      c.alt_labels.each do |l|
        concept[:altLabel] ||= []
        concept[:altLabel] << l.value
      end
      concept
    end
    raw_hash = {
        "@context": "https://openactive.io/",
        id: "https://openactive.io/#{ENV['VOCAB_IDENTIFIER']}",
        title: "OpenActive #{ENV['VOCAB_NAME']}",
        description: "#{ENV['VOCAB_DESCRIPTION']}",
        type: "ConceptScheme",
        license: "https://creativecommons.org/licenses/by/4.0/",
        concept: concepts
    }
    JSON.pretty_generate(raw_hash)
  end

  def generate_collection_json(c)
    collectionname = c.origin[1..-1]
    filename = "collections/#{collectionname}.jsonld"
    url = "https://openactive.io/#{ENV['VOCAB_IDENTIFIER']}/#{filename}"
    members = []
    c.concepts.each do |rel|
      members << "https://openactive.io/#{ENV['VOCAB_IDENTIFIER']}##{rel.origin[1..-1]}"
    end
    collection = {
        "@context": "https://openactive.io/",
        "@type": "ConceptCollection",
        "@id": url,
        prefLabel: c.pref_label.to_s,
        inScheme: "https://openactive.io/#{ENV['VOCAB_IDENTIFIER']}",
        license: "https://creativecommons.org/licenses/by/4.0/"
    }
    c.alt_labels.each do |l|
      collection[:altLabel] ||= []
      collection[:altLabel] << l.value
    end
    c.notes_for_class(Note::SKOS::Definition).each do |n|
      collection[:definition] = n.value
    end
    collection[:member] = members if members.any?
  
    JSON.pretty_generate(collection)
  end
end
