class Course < ApplicationRecord
  # PURPOSE:
  # This model represents a course in an educational platform.
  # It contains information about the course, such as its locale, name, directory path, 
  # and relationships to other models like `User` (instructor), `Institution`, `CourseTeam`, 
  # and `CourseParticipant`. The `Course` model facilitates core course management operations 
  # such as adding participants, handling assignments, and interacting with teaching assistants (TAs).
  #
  # USAGE IN OTHER CLASSES:
  # - **Assignment Model**: This class likely interacts with assignments, either through direct relationships
  #   or via helper methods like `copy_participants`. Assignments probably rely on `Course` to organize 
  #   which course each assignment belongs to.
  # - **User Model**: The `User` model interacts with `Course` by establishing the instructor-student 
  #   relationship. A user can be an instructor of a course or a participant (student) in the course.
  # - **CourseParticipant**: This class helps to manage the relationships between users and courses, allowing
  #   users to be assigned as participants. It uses the `Course` class as a parent entity and contains user
  #   permissions or roles in the course context.
  # - **CourseTeam**: Teams within the course are likely used to organize students for group assignments or 
  #   projects. `Course` provides a way to query, create, and manage these teams.
  # - **Institution Model**: The `Course` belongs to an institution, which provides institutional context 
  #   (e.g., university, college).

  # `enum` defines a set of possible values for the `locale` attribute. The values for `locale` 
  # are provided by the `Locale.code_name_to_db_encoding` method, which translates the locale's 
  # code names to their database encodings.
  enum locale: Locale.code_name_to_db_encoding

  # Associations

  # A course has many TA (Teaching Assistant) mappings, which track the relationship between TAs and courses.
  # If the course is deleted, the TA mappings are also destroyed.
  has_many :ta_mappings, dependent: :destroy

  # A course has many TAs, connected via the `ta_mappings` relationship. This sets up a many-to-many relationship
  # where multiple TAs can be associated with a single course.
  has_many :tas, through: :ta_mappings

  # A course can have multiple assignments, which are destroyed if the course is deleted.
  # This helps to organize coursework related to the course.
  has_many :assignments, dependent: :destroy

  # The course belongs to a specific instructor, who is a `User`. The foreign key `instructor_id`
  # is used to link the course to the user who is teaching it.
  belongs_to :instructor, class_name: 'User', foreign_key: 'instructor_id'

  # The course belongs to an institution (e.g., university, school), which is referenced by the foreign key `institutions_id`.
  # This ties the course to an educational institution.
  belongs_to :institution, foreign_key: 'institutions_id'

  # A course can have multiple participants (students), which are linked via the `CourseParticipant` model.
  # The `foreign_key: 'parent_id'` indicates that this course is the parent entity.
  has_many :participants, class_name: 'CourseParticipant', foreign_key: 'parent_id', dependent: :destroy

  # A course can have multiple teams, linked by the `CourseTeam` model. This is typically used for organizing
  # students into groups for projects or assignments.
  has_many :course_teams, foreign_key: 'parent_id', dependent: :destroy

  # Each course has one associated `course_node`, which could be used for navigation or hierarchical structure.
  # This is deleted if the course is deleted.
  has_one :course_node, foreign_key: 'node_object_id', dependent: :destroy

  # A course can have multiple notifications, such as reminders or updates related to the course.
  # These are destroyed when the course is deleted.
  has_many :notifications, dependent: :destroy

  # Enables versioning for the `Course` model using the `paper_trail` gem. This tracks changes to the course
  # and allows reverting to previous versions if needed.
  has_paper_trail

  # Validations ensure that a course has a name and directory path, as these are essential for proper identification
  # and file storage.
  validates :name, presence: true
  validates :directory_path, presence: true

  # Custom Methods

  # This method returns all predefined teams associated with this course.
  # It queries the `CourseTeam` model for any teams linked to this course via the `parent_id`.
  def get_teams
    CourseTeam.where(parent_id: id)
  end

  # This method returns the directory path for submissions related to the course. The path is constructed based
  # on the instructor's name and the course's directory path.
  # The `FileHelper.clean_path` method ensures that the paths are properly formatted.
  def path
    # Raise an error if there is no instructor assigned to the course, as the path cannot be generated without it.
    raise 'Path can not be created. The course must be associated with an instructor.' if instructor_id.nil?

    # Construct the path by joining the instructor's name and the course's directory path.
    Rails.root + '/pg_data/' + FileHelper.clean_path(User.find(instructor_id).name) + '/' + FileHelper.clean_path(directory_path) + '/'
  end

  # Returns all participants (students) associated with the course by querying the `CourseParticipant` model.
  def get_participants
    CourseParticipant.where(parent_id: id)
  end

  # Returns a specific participant by `user_id`, querying the `CourseParticipant` model.
  def get_participant(user_id)
    CourseParticipant.where(parent_id: id, user_id: user_id)
  end

  # Adds a participant to the course by their `user_name`. If the user does not exist, it raises an error.
  # If the user is already a participant in the course, it also raises an error.
  def add_participant(user_name)
    user = User.find_by(name: user_name)
    if user.nil?
      raise 'No user account exists with the name ' + user_name + ". Please <a href='" + url_for(controller: 'users', action: 'new') + "'>create</a> the user first."
    end

    # Check if the user is already a participant. If so, raise an error.
    participant = CourseParticipant.where(parent_id: id, user_id: user.id).first
    if participant
      raise "The user #{user.name} is already a participant."
    else
      # Create a new participant for the course.
      CourseParticipant.create(parent_id: id, user_id: user.id, permission_granted: user.master_permission_granted)
    end
  end

  # Copies participants from an assignment to the course.
  # It adds each participant from the specified assignment (by `assignment_id`) to the course.
  # If an error occurs (e.g., the user is already a participant), it accumulates the errors and raises them at the end.
  def copy_participants(assignment_id)
    participants = AssignmentParticipant.where(parent_id: assignment_id)
    errors = []
    error_msg = ''

    # For each participant in the assignment, attempt to add them to the course.
    participants.each do |participant|
      user = User.find(participant.user_id)

      begin
        add_participant(user.name)
      rescue StandardError
        errors << $ERROR_INFO # Capture any errors during the process
      end
    end

    # If there are errors, raise them as a single error message.
    unless errors.empty?
      errors.each do |error|
        error_msg = error_msg + '<BR/>' + error if error
      end
      raise error_msg
    end
  end

  # Checks if a given user is part of any team in the course.
  def user_on_team?(user)
    teams = get_teams
    users = []
    
    # Iterate through all teams and collect users
    teams.each do |team|
      users << team.users
    end

    # Flatten the list of users and check if the given user is part of it.
    users.flatten.include? user
  end

  # External Dependency
  # The `CourseAnalytic` module, likely provides methods for analyzing the course data. 
  # This module could include features like course performance analysis, student participation analysis, etc.
  require 'analytic/course_analytic'
  include CourseAnalytic
end
