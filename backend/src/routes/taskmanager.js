const express = require('express');
const router = express.Router();
const taskManagerController = require('../controllers/taskManagerController');
const auth = require('../middleware/auth');

// Protected routes
router.use(auth);

router.get('/stats', taskManagerController.getTaskStats);
router.get('/', taskManagerController.getAllTasks);
router.post('/', taskManagerController.createTask);
router.get('/:id', taskManagerController.getTask);
router.put('/:id', taskManagerController.updateTask);
router.delete('/:id', taskManagerController.deleteTask);

module.exports = router;
