import React, { useState } from "react";
import { Box, Button, TextField, Typography } from "@mui/material";
import FileUploadField from "../components/FIleUploadField";
import "../styles/RegisterPage.css";

const RegisterPage = () => {
  const [formData, setFormData] = useState({
    username: "",
    email: "",
    password: "",
    phone_number: "",
    address: "",
    cpn: "",
    age: "",
    photo: null,
  });

  const handleInputChange = (e) => {
    const { name, value } = e.target;
    setFormData({ ...formData, [name]: value });
  };

  const handlePhotoChange = (e) => {
    setFormData({ ...formData, photo: e.target.files[0] });
  };

  const handleSubmit = (e) => {
    e.preventDefault();
    console.log("Form Data Submitted:", formData);
  };

  return (
    <div className="register-page">
      <div className="background-image"></div>
      <Box className="form-box">
        <Typography variant="h4" gutterBottom>
          Register
        </Typography>
        <form onSubmit={handleSubmit}>
          <TextField
            fullWidth
            required
            label="Username"
            name="username"
            value={formData.username}
            onChange={handleInputChange}
            margin="normal"
          />
          <TextField
            fullWidth
            required
            type="email"
            label="Email"
            name="email"
            value={formData.email}
            onChange={handleInputChange}
            margin="normal"
          />
          <TextField
            fullWidth
            required
            type="password"
            label="Password"
            name="password"
            value={formData.password}
            onChange={handleInputChange}
            margin="normal"
          />
          <TextField
            fullWidth
            required
            label="Phone Number"
            name="phone_number"
            value={formData.phone_number}
            onChange={handleInputChange}
            margin="normal"
          />
          <TextField
            fullWidth
            required
            label="Address"
            name="address"
            value={formData.address}
            onChange={handleInputChange}
            margin="normal"
          />
          <TextField
            fullWidth
            required
            label="CNP"
            name="cpn"
            value={formData.cpn}
            onChange={handleInputChange}
            margin="normal"
          />
          <TextField
            fullWidth
            label="Age"
            name="age"
            value={formData.age}
            onChange={handleInputChange}
            margin="normal"
          />
          <FileUploadField />
          <Button
            variant="contained"
            color="primary"
            type="submit"
            size="large"
            fullWidth
            sx={{ mt: 3 }}
          >
            Register
          </Button>
        </form>
      </Box>
    </div>
  );
};

export default RegisterPage;
