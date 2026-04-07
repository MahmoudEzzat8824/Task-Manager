const TaskManager = require('../models/TaskManager');

// @desc    Get all tasks from taskmanager collection
// @route   GET /api/taskmanager
// @access  Public
exports.getAllTasks = async (req, res) => {
  try {
    const { status, priority, category, sort } = req.query;
    
    // Build query
    const query = {};
    if (status) query.status = status;
    if (priority) query.priority = priority;
    if (category) query.category = category;

    // Build sort
    let sortOption = { createdAt: -1 };
    if (sort === 'dueDate') sortOption = { dueDate: 1 };
    if (sort === 'priority') {
      const priorityOrder = { high: 1, medium: 2, low: 3 };
      sortOption = { priority: 1, createdAt: -1 };
    }
    if (sort === 'title') sortOption = { title: 1 };

    const tasks = await TaskManager.find(query).sort(sortOption);

    res.json({
      success: true,
      count: tasks.length,
      data: tasks,
    });
  } catch (error) {
    console.error('Get tasks error:', error);
    res.status(500).json({
      success: false,
      message: 'Error fetching tasks',
      error: process.env.NODE_ENV === 'production' ? undefined : error.message,
    });
  }
};

// @desc    Get single task by ID
// @route   GET /api/taskmanager/:id
// @access  Public
exports.getTask = async (req, res) => {
  try {
    const task = await TaskManager.findById(req.params.id);

    if (!task) {
      return res.status(404).json({
        success: false,
        message: 'Task not found',
      });
    }

    res.json({
      success: true,
      data: task,
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: 'Error fetching task',
      error: process.env.NODE_ENV === 'production' ? undefined : error.message,
    });
  }
};

// @desc    Create new task
// @route   POST /api/taskmanager
// @access  Public
exports.createTask = async (req, res) => {
  try {
    const task = await TaskManager.create(req.body);

    res.status(201).json({
      success: true,
      message: 'Task created successfully',
      data: task,
    });
  } catch (error) {
    console.error('Create task error:', error);
    res.status(400).json({
      success: false,
      message: error.message || 'Error creating task',
    });
  }
};

// @desc    Update task
// @route   PUT /api/taskmanager/:id
// @access  Public
exports.updateTask = async (req, res) => {
  try {
    const task = await TaskManager.findByIdAndUpdate(
      req.params.id,
      { ...req.body, updatedAt: Date.now() },
      { new: true, runValidators: true }
    );

    if (!task) {
      return res.status(404).json({
        success: false,
        message: 'Task not found',
      });
    }

    res.json({
      success: true,
      message: 'Task updated successfully',
      data: task,
    });
  } catch (error) {
    res.status(400).json({
      success: false,
      message: error.message || 'Error updating task',
    });
  }
};

// @desc    Delete task
// @route   DELETE /api/taskmanager/:id
// @access  Public
exports.deleteTask = async (req, res) => {
  try {
    const task = await TaskManager.findByIdAndDelete(req.params.id);

    if (!task) {
      return res.status(404).json({
        success: false,
        message: 'Task not found',
      });
    }

    res.json({
      success: true,
      message: 'Task deleted successfully',
      data: task,
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: 'Error deleting task',
      error: process.env.NODE_ENV === 'production' ? undefined : error.message,
    });
  }
};

// @desc    Get task statistics
// @route   GET /api/taskmanager/stats
// @access  Public
exports.getTaskStats = async (req, res) => {
  try {
    const totalTasks = await TaskManager.countDocuments();
    const pendingTasks = await TaskManager.countDocuments({ status: 'pending' });
    const inProgressTasks = await TaskManager.countDocuments({ status: 'in-progress' });
    const completedTasks = await TaskManager.countDocuments({ status: 'completed' });
    
    const highPriority = await TaskManager.countDocuments({ priority: 'high' });
    const mediumPriority = await TaskManager.countDocuments({ priority: 'medium' });
    const lowPriority = await TaskManager.countDocuments({ priority: 'low' });
    
    const categories = await TaskManager.distinct('category');

    res.json({
      success: true,
      data: {
        total: totalTasks,
        byStatus: {
          pending: pendingTasks,
          'in-progress': inProgressTasks,
          completed: completedTasks,
        },
        byPriority: {
          high: highPriority,
          medium: mediumPriority,
          low: lowPriority,
        },
        categories,
      },
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: 'Error fetching statistics',
      error: process.env.NODE_ENV === 'production' ? undefined : error.message,
    });
  }
};
