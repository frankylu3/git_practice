class EmailTemplate

  # these are NOT action mailer methods anymore.
  # this class contains methods for generating system emails;
  # each one returns a saved EmailArchive object, which can then
  # be passed to the actual delivery method (BpaMail.deliver_email)
  #
  # Note: this was done to get the mail in the database before sending, but
  # there are better ways to achieve this, such as:
  # 1. use action mailer create_* methods, save the resulting TMail (eg, gmail)
  # 2. use something like ar_mailer plugin (eg, elections)

  # note: includes all elements on the current/destination state, regardless
  # of secret flags or visibility rules.
  # by default, it will send to the environment-dependant touchpaper email
  # address.  pass 'destination_address' to a different address to override.
  # this can have multiple values - pass a string separated by a semi-colon.
  
  def self.dataActivation(submission, url, m)
    required = ["Name", "Email", "Contact Number", "Campus", "Building", "Room", "Wall Port Number", "Mac Address", "Comments", "Dept ID", "Project Code", "Approving Officer"]
    i = 0
    contact = false
    building = false
    form = submission.form
    m.subject = "#{form.name_with_request} ##{submission.id}" + " | Data Activation"
    m.body = ""

    current_values = submission.current_values
    submission.state.state_elements.order(
        "#{form.element_ordering_table}.page_order"
        ).includes(:element).references(:element).all.each do |se|
        el = se.element
        
        if i == 0 and contact == false
          m.body += "\nContact Details \n \n"
          contact = true
        elsif i == 3 and building == false

          m.body += "\nBuilding Details \n \n" 
          building = true
        end

        if el.description == required[i]
          i += 1
          description = el.description
          if current_values[el.name]
            if el.show_related_only? and current_values[el.name].related_value.present?
              value = current_values[el.name].related_value
            else
              value = current_values[el.name].value
              value += " - #{current_values[el.name].related_value}" if current_values[el.name].related_value.present?
            end
          else
            value = ""
          end

          if description.length > 30 and value.present?
            m.body += "#{description}:\n"
            m.body += "#{" " * 32}#{value}\n"
          else
            m.body += "#{description.ljust(30)}: #{value}\n"
          end
        end

      end

    m.body += "\n"
    m.body += "Original Online Request: #{url}\n"
    if submission.person
      m.from_address = "#{submission.person.name} <#{submission.person.mail}>"
    end
    m.sent = false
    m.save!

    return m
  end

  def self.voicemail(submission, url, m)
    required = ["Name/ID", "Contact Phone Number", "Action Required", "University Extension Number for Voicemail box", "Other Comments"]
    values = Array.new(5)
    valueDescription = ["Name", "Phone Number", "Action Required", "Extension Number", "Comments"]
    form = submission.form
    i=0
    m.body = ""
    
    submission.state.state_elements.order(
        "#{form.element_ordering_table}.page_order"
        ).includes(:element).references(:element).all.each do |se|
        el = se.element

        current_values = submission.current_values
        if el.description == required[i]
          
          # description = el.description
          values[i] = current_values[el.name].value
          values[i] += " - #{current_values[el.name].related_value}" if current_values[el.name].related_value.present?

          i += 1
          # if description.length > 30 and value.present?
          #   m.body += "#{description}:\n"
          #   m.body += "#{" " * 32}#{value}\n"
          # else
          #   m.body += "#{description.ljust(30)}: #{value}\n"
          # end
        end

      end

      for index in 0..4 do
          m.body += "#{valueDescription[index].ljust(30)}: #{values[index]}\n"
      end

      if submission.person
        m.from_address = "#{submission.person.name} <#{submission.person.mail}>"
      end
      
      m.sent = false
      m.save!

      return m

  end

  def self.notify_touchpaper(submission, url, destination_address)
    destination_address = BpaConfig.touchpaper_email if destination_address.blank?
    form = submission.form
    m = EmailArchive.new
    m.form_id = form.id
    m.person_id = nil       # not being sent to a person
    m.submission_id = submission.id
    m.destination_address = destination_address
    m.recipient_name = nil  # omit "Dear ..."
    m.subject = "#{form.name_with_request} ##{submission.id}"
    m.subject << ": #{submission.details}" if submission.details.present?
    m.subject = m.subject[0,250]
    m.with_attachments = true # causes BpaMailer class to add attachments
    m.body = ""
    dataActivationMatch = 0

    @multi = Submission.where("multi_parent_id = ?", submission.id).all
    original_submission = submission
    @count = 0
    (0..@multi.count).each do |i|
      if i == 0
        m.body += "** MULTI REQUEST **" if @multi.count>0
        submission = original_submission
      else
        @count = i
        m.body += ""
        m.body += "** REQUEST ##{i+1} **"
        submission = @multi[i-1]
      end

      current_values = submission.current_values
      submission.state.state_elements.order(
        "#{form.element_ordering_table}.page_order"
        ).includes(:element).references(:element).all.each do |se|
        el = se.element

        next if @count>0 && !se.element.multiple_allowed #if multi request, but not multi field

        visel = el.visibility_element
        if visel
          other_value = current_values[visel.name].to_s
          if el.visibility_element_values.blank?
            next if other_value.blank?
          else
            next unless el.visibility_element_values.split(',').index(other_value)
          end
        end

        if el.element_type == "statictext"
          text = el.static_text.chomp
          # strip html - very rudimentary, but covers common usage in bpa.
          # any redcloth markup is better left in.
          text.gsub!(/<a [^>]*>(.*?)<\/a>/, '\1')
          text.gsub!(/<br[^>]*>/, "\n")
          m.body += "\n#{text}\n"
        else
          description = el.description
          if current_values[el.name]
            if el.show_related_only? and current_values[el.name].related_value.present?
              value = current_values[el.name].related_value
              value += " IF "
            else
              value = current_values[el.name].value
              value += " - #{current_values[el.name].related_value}" if current_values[el.name].related_value.present?
              value += " ELSE "
            end
          else
            value = ""
          end

          #Checking for Data and Voice Request for Data Activation 
          if form.name_with_request == "Data 

            and Voice Request" 
            if el.description == "Request Type"
              if value == "New Communications Service (Voice & Data)"
                dataActivationMatch += 1
              end
            elsif el.description == "New Outlet Required"
              if value == "No"
                dataActivationMatch += 1
              end
            elsif el.description == "Add Phone Service"
              if value == "No"
                dataActivationMatch += 1
              end
            end

            # runs when it is a data activation request
            if dataActivationMatch == 3 
              return dataActivation(submission, url, m)
            end
          end

          #Checking for Data and Voice Request for Data Activation 
          if form.name_with_request == "Voicemail Request"
            return voicemail(submission, url, m) 
          end

          if description.length > 30 and value.present?
            m.body += "#{description}:\n"
            m.body += "#{" " * 32}#{value}\n"
          else
            m.body += "#{description.ljust(30)}: #{value}\n"
          end
        end
      end

    end

    # Add history
    m.body += "\n"
    m.body += "Submission History\n"
    m.body += "------------------\n"
    submission.visible_submission_history(submission.person).each do |h|
      if h.person
        updated_by = "#{h.person_id} #{h.person.name}"
      else
        updated_by = "automatic process"
      end
      m.body += "#{h.created_at.strftime("%a %d/%m/%Y %H:%M")} (#{updated_by}) #{h.details}\n"
    end

    m.body += "\n"
    m.body += "Original Online Request: #{url}\n"

    if submission.person
      m.from_address = "#{submission.person.name} <#{submission.person.mail}>"
    end
    m.sent = false
    m.save!
    return m
  end

  def self.notify_submission_logged(submission, url)
    form = submission.form
    m = EmailArchive.new
    m.form_id = form.id
    m.person_id = submission.person.id
    m.submission_id = submission.id
    m.destination_address = "#{submission.person.name} <#{submission.person.mail}>"
    m.recipient_name = submission.person.name
    m.subject = "Request logged with the Service Desk: #{form.name} ##{submission.id}"
    m.subject << ": #{submission.details}" unless submission.details.blank?
    m.subject = m.subject[0,250]
    m.body = "Your #{form.name_with_request} ##{submission.id.to_s} has been successfully logged in the online requests system, and is awaiting processing.

You may review the status of your request at any time at: #{url}

This e-mail is an automatically generated system message."
    m.from_address = "#{form.name} <#{form.form_contact.mail}>"
    signature = form.form_contact.signature
    m.body += "\n\n#{signature}"
    m.sent = false
    m.save!
    return m
  end

  def self.notify_state_change(submission, transition, url)
    next_state = transition.next_state
    form = next_state.form

    m = EmailArchive.new
    m.form_id = form.id
    m.person_id = nil
    m.submission_id = submission.id

    # if the transition has a fully custom subject configured, use it, else generate one
    if transition.email_subject.nil? or transition.email_subject.empty?
      m.subject = "#{form.name} ##{submission.id}"
      m.subject << ": #{submission.details}" unless submission.details.blank?
    else
      m.subject = transition.email_subject.gsub(
        /\$ID\b/, submission.id.to_s).gsub(
        /\$Form\b/, form.name).gsub(
        /\$Requester\b/, submission.requester_name)
    end
    m.subject = m.subject[0,250]

    m.from_address = "#{form.name} <#{form.form_contact.mail}>"
    signature = form.form_contact.signature

    m.sent = false

    if transition.email_option == "submitter"
      if submission.person
        m.person_id = submission.person.id
        recipient_name = submission.person.name
        recipient_mail = submission.person.mail
      else
        # need a way to send email to the original submitter...
        return nil
      end
    elsif transition.email_option == "responsible"
      recipient_name, recipient_mail = case next_state.responsibility
      when "submitter"  then [submission.person.name, submission.person.mail]
      when "individual" then [submission.responsible_person.name ,submission.responsible_person.mail]
      when "group"      then next_state.work_in_progress ? [submission.responsible_person.name, submission.responsible_person.mail] : [next_state.group.name, next_state.group.mail]
      else raise ArgumentError, "state ##{next_state.id} has an invalid responsibility '#{next_state.responsibility}'"
      end
      if next_state.responsibility == "individual"
        m.person_id = submission.person.id
      end
    else
      raise ArgumentError, "transition ##{transition.id} has an invalid email option '#{transition.email_option}'"
    end
    email_addresses = recipient_mail.split(';')
    m.destination_address = email_addresses.map{|e| "#{recipient_name} <#{e}>"}.join('; ')
    m.recipient_name = recipient_name
    m.body = transition.email_body.gsub(
      /\$ID\b/, submission.id.to_s).gsub(
      /\$URL\b/, url).gsub(
      /\$Form\b/, form.name).gsub(
      /\$Details\b/, submission.details).gsub(
      /\$Requester\b/, submission.requester_name)
    m.body += "\n\n#{signature}"
    m.save!
    return m
  end

  # For New Starter Form:

  def self.notify_person(submission, url, person, email_body)
    form = submission.form
    m = EmailArchive.new
    m.form_id = form.id
    m.person_id = person.id
    m.submission_id = submission.id
    m.destination_address = "#{person.name} <#{person.mail}>"
    m.recipient_name = person.name
    m.subject = "#{form.name} ##{submission.id}"
    m.subject << ": #{submission.details}" unless submission.details.blank?
    m.subject = m.subject[0,250]
    m.body = email_body.gsub(
      /\<ID>/, submission.id.to_s).gsub(
      /\<URL>/, url).gsub(
      /\<Details>/, submission.details).gsub(
      /\<Form>/, form.name_with_request)
    m.from_address = "#{form.name} <#{form.form_contact.mail}>"
    signature = form.form_contact.signature
    m.body += "\n\n#{signature}"
    m.sent = false
    m.save!
    return m
  end

  def self.notify_group(submission, url, group, email_body)
    form = submission.form
    m = EmailArchive.new
    #p = Person.find(person_id)
    m.form_id = form.id
    m.person_id = nil
    m.submission_id = submission.id
    m.destination_address = "#{group.name} <#{group.mail}>"
    m.recipient_name = group.name
    m.subject = "#{form.name} ##{submission.id}"
    m.subject << ": #{submission.details}" unless submission.details.blank?
    m.subject = m.subject[0,250]
    m.body = email_body.gsub(
      /\<ID>/, submission.id.to_s).gsub(
      /\<URL>/, url).gsub(
      /\<Details>/, submission.details).gsub(
      /\<Form>/, form.name_with_request)
    m.from_address = "#{form.name} <#{form.form_contact.mail}>"
    signature = form.form_contact.signature
    m.body += "\n\n#{signature}"
    m.sent = false
    m.save!
    return m
  end

    def self.notify_by_email(submission, url, email, name, email_body)
    form = submission.form
    m = EmailArchive.new
    #p = Person.find(person_id)
    m.form_id = form.id
    m.person_id = nil
    m.submission_id = submission.id
    m.destination_address = "#{name} <#{email}>"
    m.recipient_name = name
    m.subject = "#{form.name} ##{submission.id}"
    m.subject << ": #{submission.details}" unless submission.details.blank?
    m.subject = m.subject[0,250]
    m.body = email_body.gsub(
      /\<ID>/, submission.id.to_s).gsub(
      /\<URL>/, url).gsub(
      /\<Details>/, submission.details).gsub(
      /\<Form>/, form.name_with_request)
    m.from_address = "#{form.name} <#{form.form_contact.mail}>"
    signature = form.form_contact.signature
    m.body += "\n\n#{signature}"
    m.sent = false
    m.save!
    return m
  end

end

