module ActiveRecord
  module Acts #:nodoc:
    module HasMany
      
      # class methods for use in model
      #   +acts_has_many_for+
      #   +acts_has_many+ 
      #
      #   the last method added:
      #
      #   class method:
      #     +has_many_through_update+
      #     +dependent_relations+
      #     +compare+
      #   
      #   Instance methods:
      #     +model+
      #     +has_many_update+
      #     +has_many_update!+
      #     +update_with_<relation>+
      #     +actuale?+
      #
      #   set +before_destroy+ callback;

      def self.included(base)
        base.extend(ClassMethods)
      end
      
      #
      # Acts Has Many gem is for added functional to work 
      # with +has_many+ relation (additional is has_many :trhough)
      # 
      # +acts_has_many+ and +acts_has_many_for+ are class methods for all model,
      # and you can use them for connection acts_has_many functional to necessary model
      # acts_has_many set in model where is has_many relation and 
      # acts_has_many_for in model where use model with acts_has_many
      #
      #   class Education < ActiveRecord::Base
      #     belongs_to :location
      #     ...
      #     acts_has_many_for :location
      #   end
      #   
      #   class Location < ActiveRecord::Base
      #     has_many :educaitons
      #     acts_has_many
      #   end
      #        
      # You can use +acts_has_many+ methods without +acts_has_many_for+
      #
      #   class Education < ActiveRecord::Base
      #     belongs_to :location
      #     ...
      #   end
      #   
      #   class Location < ActiveRecord::Base
      #     has_many :education
      #     acts_has_many
      #   end
      #         
      # in this case you can use nex function:
      #   
      #   education = Education.first
      #   location = education.location # get location from education
      #
      #   new_id, del_id = location.has_many_update(data: {title:"Kyiv"}, relation: :educations)
      #   # or simple
      #   new_id, del_id = location.has_many_update({title:"Kyiv"}, :educations)
      #   # or with dinamic methods helper
      #   new_id, del_id = location.update_with_educations {title:"Kyiv"}
      # 
      #   # you can also use has_many_update! which updated relation with parent row without you
      #   location.has_many_update!({title: "Kyiv"}, education)
      #
      # with usage +acts_has_many_for+ you don't need set relation and give parent row in case with has_many_update!
      # but you need get row for update get per ralation from parent row (see above with location row) in other case
      # you can't use it becaus methods will not know about relation and paren row for update it.
      #
      #   new_id, del_id = location.has_many_update {title:"Kyiv"}
      #   # and
      #   location.has_many_update! {title:"Kyiv"}
      #
      
      module ClassMethods

        #
        # +acts_has_many_for+: use with +acts_has_many+
        #   use for set link between parent row and child
        # options: list relations (symbol)
        #
                
        def acts_has_many_for(*relations)
          relations.each do |relation|
            relation = relation.to_s
            class_eval <<-EOV
              def #{relation}
                row = #{relation.classify}.find #{relation.foreign_key}
                row.tmp_parrent_id = id
                row.tmp_current_relation = '#{self.name.tableize}'
                row
              end
            EOV
          end
        end

        #
        # +acts_has_many+ - available method in all model and switch on 
        #   extension functional in concrete model (need located this method
        #   after relation which include in dependence, or anywhere but set depend relation)
        # options
        #   :compare( symbol, string)- name column for compare with other element in table
        #   :relations( array) - concrete name of depended relation
        #   :through( boolean) - off or on has_many_through_update method
        #
        
        def acts_has_many(options = {})
          dependent_relations = []
          options_default = { compare: :title, through: false }

          options = options_default.merge options
              
          options[:relations] = self.reflect_on_all_associations(:has_many)
            .map{|o| o.name} if options[:relations].nil?
           
          options[:relations].each do |relation|
            dependent_relations << relation.to_s.tableize
          end
         
          #
          # +has_many_through_update+ (return array) [ 1 - array objects records, 2 - array delete ids ] 
          # options 
          #   :update( array) - data for update (id and data)
          #   :new( array) - data for create record (data)
          #
          # +for delete need use method destroy !!!+
          #

          has_many_through = ''
          if(options[:through])
            has_many_through = """
              def self.has_many_through_update(options)
                record_add = []
                record_del = []
  
                # update
                options[:update].each do |id, data|
                  add, del = #{self}.find(id)
                    .has_many_update(:data => data, :relation => options[:relation])
                  record_add << add unless add.nil?
                  record_del << del unless del.nil?
                end unless options[:update].nil?
                
                # new
                unless options[:new].nil?
                  options[:new].uniq!
                  options[:new].each do |data|
                    data = data.symbolize_keys
                    record_add << #{self}
                      .where('#{options[:compare]}' => data['#{options[:compare]}'.to_sym])
                      .first_or_create(data)
                    record_del.delete record_add.last.id
                  end 
                end
                
                record_add = #{self}.where('id IN (?)', record_add) unless record_add.empty? 
                [record_add, record_del]
              end """
          end
          
          # add dinamic methods for example
          # update_with_<relation>(data) equal has_many_update(data, relation)
          extend_methods = ''
          dependent_relations.each do |relation|
            extend_methods += """
              def update_with_#{relation}(data)
                has_many_update data: data, relation: :#{relation}
              end
            """
          end
          
          class_eval <<-EOV
            include ActiveRecord::Acts::HasMany::InstanceMethods
            class << self
              def dependent_relations
                #{dependent_relations}
              end
              def compare
                '#{options[:compare]}'.to_sym
              end
            end

            def model
              #{self}
            end             
            
            #{extend_methods}
            #{has_many_through}
            
            attr_accessor :tmp_current_relation, :tmp_parrent_id
            before_destroy :destroy_filter
          EOV
        end
      end
      
      module InstanceMethods
        
        #
        # +has_many_update!+ identicaly to has_many_update but 
        #   You can use this method when you use +acts_has_many_for+
        #   and get object for update with help of +relation+ or give parent row
        # option
        #   data for update
        #   parrent row (maybe miss)
        #

        def has_many_update!(*data)
          if data.size == 2
            self.tmp_current_relation = data[1].class.name.tableize
            self.tmp_parrent_id = data[1].id
          end
          
          if tmp_current_relation.nil? or tmp_parrent_id.nil?
            p "ArgumentError: 'has_many_update!' don't have data about parent object"
            p "* maybe you use 'acts_has_many_for' incorrectly"
            p "* if you don't use 'acts_has_many_for' in parent model you can give parent object"
            return nil
          end

          new_id, del_id = has_many_update data[0]
          parrent = eval(tmp_current_relation.classify).find(tmp_parrent_id)
          parrent.update_attributes("#{model.name.foreign_key}" => new_id)
          parrent.save!

          destroy unless del_id.nil?
          model.find new_id
        end
        
        #
        # +has_many_update+ ( return array) [new_id, del_id]
        # options maybe Hash, or list parameters
        #   :data( type: hash) - data for updte
        #   :relation( type: str, symbol) - modifi with tableize (maybe miss)
        # 

        def has_many_update(*options)
          if options.size == 1 && options[0].include?(:data) && options[0].include?(:relation) 
            data = options[0][:data]
            relation = options[0][:relation]
          elsif options.size == 2
            data = options[0]
            relation = options[1]
          else
            relation = tmp_current_relation
            data = options[0]
          end
          
          data_default = {}
          data_default[model.compare] = ""
          data = data_default.merge data

          if relation.blank?
            p "Notice: 'has_many_update' don't know about current relation, and check all relations"
          end
          
          has_many_cleaner data.symbolize_keys, relation
        end
        
        #
        # +actuale?+ - check the acutuality of element in has_many table
        # options maybe Hash, or simple parameter
        #   :relation( string, symbol) - exclude current relation (maybe miss)
        #
        
        def actuale? (options={relation: ""})
          if options.is_a? Hash and options.include? :relation 
            relation = options[:relation].to_s.tableize
          else
            relation = options.to_s.tableize 
          end

          actuale = false
          model.dependent_relations.each do |dependent_relation|
            tmp = self.send(dependent_relation)
            if relation == dependent_relation
              actuale ||= tmp.all.size > 1
            else
              actuale ||= tmp.exists?
            end
          end
          actuale
        end
      end
      
    private
      
      #
      # +destroy_filter+ - method for before_destroy, check actuale record and
      # return true for delete or false for leave
      #

      def destroy_filter
        not actuale?
      end

      # 
      # base operations in this gem
      #

      def has_many_cleaner(data, relation)
        compare = { model.compare => data[model.compare] }
          
        object_id = id
        delete_id = nil
        
        if actuale? relation
          # create new object and finish
          object = model.where(compare).first_or_create(data)
          object_id = object.id
        else
          object_tmp = model.where(compare)[0]
          unless object_tmp.nil?
            # set new object and delete old
            delete_id = (object_id == object_tmp.id) ? nil : object_id
            object_id = object_tmp.id
          else
            # update old object
            if object_id.nil?
              object = model.where(compare).first_or_create(data)
              object_id = object.id
            else
              if data[model.compare].blank?
                delete_id = object_id
                object_id = nil
              else
                update_attributes(data)
              end
            end
          end
        end
        [object_id, delete_id]
      end
    end
  end
end
